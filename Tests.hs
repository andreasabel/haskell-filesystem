module Main (tests, main) where

import Prelude hiding (FilePath)
import Data.Word (Word8)
import Data.List (intercalate)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import Test.QuickCheck
import qualified Test.Framework as F
import Test.Framework.Providers.QuickCheck2 (testProperty)
import System.FilePath as P
import System.FilePath.CurrentOS ()
import System.FilePath.Rules

main :: IO ()
main = F.defaultMain tests

tests :: [F.Test]
tests =
	[ F.testGroup "Basic properties"
	  [ testNull
	  , testRoot
	  , testDirectory
	  , testParent
	  , testFilename
	  , testBasename
	  , testAbsolute
	  , testRelative
	  ]
	
	, F.testGroup "Basic operations"
	  [ testEquivalent
	  , testAppend
	  , testCommonPrefix
	  , testSplitExtension
	  ]
	
	, F.testGroup "To/From bytes"
	  [ testIdentity "POSIX" posix posixPaths
	  , testIdentity "Windows" windows windowsPaths
	  ]
	
	, F.testGroup "Validity"
	  [ testProperty "POSIX" $ forAll posixPaths $ valid posix
	  , testProperty "Windows" $ forAll windowsPaths $ valid windows
	  ]
	
	, testSplitSearchPath
	, testNormalise
	]

propPosix :: ((String -> FilePath) -> a) -> a
propPosix k = k (fromString posix)

propWindows :: ((String -> FilePath) -> a) -> a
propWindows k = k (fromString windows)

testProperties :: Testable t => F.TestName -> [t] -> F.Test
testProperties name = F.testGroup name . zipWith testProperty labels where
	labels = map show $ iterate (+ 1) 1

testNull :: F.Test
testNull = testProperty "null" $ P.null empty

testRoot :: F.Test
testRoot =
	let t x y = propPosix $ \p -> root (p x) == p y in
	
	testProperties "root"
	[ t "" ""
	, t "/" "/"
	, t "foo" ""
	, t "/foo" "/"
	]

testDirectory :: F.Test
testDirectory =
	let t x y = propPosix $ \p -> directory (p x) == p y in
	
	testProperties "directory"
	[ t "" "./"
	, t "/" "/"
	, t "/foo/bar" "/foo/"
	, t "/foo/bar/" "/foo/bar/"
	, t "." "./"
	, t ".." "./"
	, t "foo" "./"
	]

testParent :: F.Test
testParent =
	let t x y = propPosix $ \p -> parent (p x) == p y in
	
	testProperties "parent"
	[ t "" "./"
	, t "/" "/"
	, t "/foo/bar" "/foo/"
	, t "/foo/bar/" "/foo/"
	, t "." "./"
	, t ".." "./"
	, t "foo" "./"
	]

testFilename :: F.Test
testFilename =
	let t x y = propPosix $ \p -> filename (p x) == p y in
	
	testProperties "filename"
	[ t "" ""
	, t "/" ""
	, t "/foo/" ""
	, t "/foo/bar" "bar"
	, t "/foo/bar.txt" "bar.txt"
	]

testBasename :: F.Test
testBasename =
	let t x y = propPosix $ \p -> basename (p x) == p y in
	
	testProperties "basename"
	[ t "/foo/bar" "bar"
	, t "/foo/bar.txt" "bar"
	]

testAbsolute :: F.Test
testAbsolute = testProperties "absolute"
	[ absolute (fromString posix "/")
	, absolute (fromString posix "/foo/bar")
	, not $ absolute (fromString posix "")
	, not $ absolute (fromString posix "foo/bar")
	]

testRelative :: F.Test
testRelative = testProperties "relative"
	[ not $ relative (fromString posix "/")
	, not $ relative (fromString posix "/foo/bar")
	, relative (fromString posix "")
	, relative (fromString posix "foo/bar")
	]

testIdentity :: F.TestName -> Rules -> Gen FilePath -> F.Test
testIdentity name r gen = testProperty name $ forAll gen $ \p -> p == fromBytes r (toBytes r p)

testEquivalent :: F.Test
testEquivalent =
	let tp x y = propPosix $ \p -> equivalent posix (p x) (p y) in
	let tw x y = propWindows $ \p -> equivalent windows (p x) (p y) in
	
	testProperties "equivalent"
	[ tp "" ""
	, tp "/" "/"
	, tp "//" "/"
	, tp "/." "/."
	, tp "/./" "/"
	, tp "foo/" "foo"
	, tp "foo/" "./foo/"
	, tp "foo/./bar" "foo/bar"
	, not $ tp "foo/bar/../baz" "foo/baz"
	
	, tw "" ""
	, tw "/" "\\"
	, tw "//" "\\"
	, tw "/." "\\."
	, tw "/./" "\\"
	, tw "c://a//bc.txt" "C:\\A\\BC.TXT"
	]

testAppend :: F.Test
testAppend =
	let t x y z = propPosix $ \p -> append (p x) (p y) == p z in
	
	testProperties "append"
	[ t "" "" ""
	, t "" "b/" "b/"
	
	-- Relative to a directory
	, t "a/" "" "a/"
	, t "a/" "b/" "a/b/"
	
	-- Relative to a file
	, t "a" "" "a/"
	, t "a" "b/" "a/b/"
	, t "a/b" "c" "a/b/c"
	
	-- Absolute
	, t "/a/" "" "/a/"
	, t "/a/" "b" "/a/b"
	, t "/a/" "b/" "/a/b/"
	
	-- Second parameter is absolute
	, t "/a/" "/" "/"
	, t "/a/" "/b" "/b"
	, t "/a/" "/b/" "/b/"
	]

testCommonPrefix :: F.Test
testCommonPrefix =
	let t xs y = propPosix $ \p -> commonPrefix (map p xs) == p y in
	
	testProperties "commonPrefix"
	[ t ["", ""] ""
	, t ["/", ""] ""
	, t ["/", "/"] "/"
	, t ["foo/", "/foo/"] ""
	, t ["/foo", "/foo/"] "/"
	, t ["/foo/", "/foo/"] "/foo/"
	, t ["/foo/bar/baz.txt.gz", "/foo/bar/baz.txt.gz.bar"] "/foo/bar/baz.txt.gz"
	]

testSplitExtension :: F.Test
testSplitExtension =
	let t x (y1, y2) = propPosix $ \p -> splitExtension (p x) == (p y1, fmap B8.pack y2) in
	
	testProperties "splitExtension"
	[ t ""              ("", Nothing)
	, t "foo"           ("foo", Nothing)
	, t "foo."          ("foo", Just "")
	, t "foo.a"         ("foo", Just "a")
	, t "foo.a/"        ("foo.a/", Nothing)
	, t "foo.a/bar"     ("foo.a/bar", Nothing)
	, t "foo.a/bar.b"   ("foo.a/bar", Just "b")
	, t "foo.a/bar.b.c" ("foo.a/bar.b", Just "c")
	]

testSplitSearchPath :: F.Test
testSplitSearchPath =
	let tp x y = propPosix $ \p -> splitSearchPath posix (B8.pack x) == map p y in
	let tw x y = propWindows $ \p -> splitSearchPath windows (B8.pack x) == map p y in
	
	testProperties "splitSearchPath"
	[ tp "a:b:c" ["a", "b", "c"]
	, tp "a::b:c" ["a", ".", "b", "c"]
	, tw "a;b;c" ["a", "b", "c"]
	, tw "a;;b;c" ["a", "b", "c"]
	]

testNormalise :: F.Test
testNormalise =
	let tp x y = propPosix $ \p -> normalise posix (p x) == p y in
	let tw x y = propWindows $ \p -> normalise windows (p x) == p y in
	
	testProperties "normalise"
	[ tp "" ""
	, tp "/" "/"
	, tp "//" "/"
	, tp "/." "/."
	, tp "/./" "/"
	, tp "foo/bar.d/" "foo/bar.d"
	
	, tw "" ""
	, tw "/" "\\"
	, tw "//" "\\"
	, tw "/." "\\."
	, tw "/./" "\\"
	, tw "c://a//bc.txt" "C:\\a\\bc.txt"
	]

instance Arbitrary Rules where
	arbitrary = elements [posix, windows]

posixPaths :: Gen FilePath
posixPaths = sized $ fmap merge . genComponents where
	merge = fromString posix . intercalate "/"
	validChar c = not $ elem c ['\x00', '/']
	component = do
		size <- choose (0, 10)
		vectorOf size $ arbitrary `suchThat` validChar
	genComponents n = do
		cs <- vectorOf n component
		frequency [(1, return cs), (9, return ([""] ++ cs))]

windowsPaths :: Gen FilePath
windowsPaths = sized $ \n -> genComponents n >>= merge where
	merge cs = do
		root <- genRoot
		let path = intercalate "\\" cs
		return $ fromString windows $ root ++ path
		
	reserved = ['\x00'..'\x1F'] ++ ['/', '\\', '?', '*', ':', '|', '"', '<', '>']
	validChar c = not $ elem c reserved
	component = do
		size <- choose (0, 10)
		vectorOf size $ arbitrary `suchThat` validChar
	genComponents n = do
		cs <- vectorOf n component
		frequency [(1, return cs), (9, return ([""] ++ cs))]
	
	genRoot = do
		let upperChar = elements ['A'..'Z']
		label <- frequency [(1, return Nothing), (9, fmap Just upperChar)]
		return $ case label of
			Just c -> [c, ':', '\\']
			Nothing -> "\\"
