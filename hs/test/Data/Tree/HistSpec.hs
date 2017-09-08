module Data.Tree.HistSpec where

import qualified Data.Vector as V
import qualified Data.Text as T

import CSSR.Prelude.Test
import Data.Tree.Hist
import qualified Data.MTree.Parse as MParse (getAlphabet, buildTree)
import qualified Data.Tree.Parse as Parse

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "navigate" $ do
    findsJust []
    findsJust ["c"]
    findsNothing ["a"]
    findsNothing ["b"]
    findsJust ["c","c"]
    findsNothing ["a","c"]
    findsJust ["b","c"]

  describe "convert" $ do
    it "removes the last children from a Parse Tree" $
      all (isNothing . navigate tree . V.fromList) $ (fmap.fmap) T.singleton ["abc", "bcc"]
    it "keeps the children of last depth" $
      all (isJust . navigate tree . V.fromList) $ (fmap.fmap) T.singleton ["bc", "cc"]

  where
    findsJust :: [Event] -> Spec
    findsJust path = do
      let node = findNode path
      it ("finds node " ++ show path) $ isJust node
      it ("node " ++ show path ++ "'s path matches") $
        maybe False ((V.fromList path ==) . view (body . obs)) node

    findsNothing :: [Event] -> Spec
    findsNothing path =
      it ("fails to find node " ++ show path) $
        isNothing . navigate tree . V.fromList $ path

    findNode :: [Event] -> Maybe Leaf
    findNode path = navigate tree . V.fromList $ path

    ptree :: Parse.Tree
    ptree = MParse.buildTree 2 (V.fromList $ T.singleton <$> "abcc")

    tree :: Tree
    tree = convert ptree (MParse.getAlphabet ptree)


