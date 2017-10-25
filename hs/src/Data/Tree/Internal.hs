{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
module Data.Tree.Internal where

import Data.Functor.Identity (Identity(..))
import CSSR.Prelude
import CSSR.Probabilistic (Probabilistic, TestResult(..))
import qualified CSSR.Probabilistic as Prob
import qualified Data.Text as T
import qualified Data.Vector as V


-- | === Homogeneity
-- Psuedocode from paper:
--   INPUTS: looping node, parse tree
--   COLLECT all next-step histories from looping node in parse tree
--   FOR each history in next-step histories
--     FOR each child in history's children
--       IF child's distribution ~/=  node's distribution
--       THEN RETURN false
--       ENDIF
--     ENDFOR
--   ENDFOR
--   RETURN TRUE
--
isHomogeneous
  :: (parent -> [Vector Integer])
  -> Double
  -> (parent, Vector Integer)
  -> Bool
isHomogeneous getChildDists sig parent =
  runIdentity $ isHomogeneousM (pure . getChildDists) sig parent

isHomogeneousM
  :: Monad m
  => (parent -> m [Vector Integer])
  -> Double
  -> (parent, Vector Integer)
  -> m Bool
isHomogeneousM getChildDists sig (parent, pdist) =
  all ((== Significant) . Prob.matchesFreqs sig pdist)
  <$> getChildDists parent


navigate :: forall lf . (lf -> Event -> Maybe lf) -> lf -> Vector Event -> Maybe lf
navigate lookup rt history =
  runIdentity $ navigateM (\a b -> pure $ lookup a b) rt history


navigateM :: forall lf m . Monad m => (lf -> Event -> m (Maybe lf)) -> lf -> Vector Event -> m (Maybe lf)
navigateM lookup rt (V.toList -> history)
  | null history = pure (Just rt)
  | otherwise    = go history rt
  where
    -- FIXME: use MaybeT here
    go :: [Event] -> lf -> m (Maybe lf)
    go [] lf = pure (Just lf)
    go os@(x:_) lf = case splitLast os of
      Nothing      -> impossible "nonempty here"
      Just (os, o) -> lookup lf o
        >>= \case
          Just ch -> go os ch
          Nothing -> pure Nothing

    splitLast :: [a] -> Maybe ([a], a)
    splitLast = \case
      [] -> Nothing
      as -> Just (init as, last as)


-- | returns ancestors in order of how they should be processed
getAncestors :: (l -> Maybe l) -> l -> [l]
getAncestors getParent l =
  runIdentity $ getAncestorsM (pure . getParent) l

getAncestorsM :: forall l m . Monad m => (l -> m (Maybe l)) -> l -> m [l]
getAncestorsM getParent l = getParent l >>= go []
  where
    go :: [l] -> Maybe l -> m [l]
    go ancestors  Nothing = pure ancestors
    go ancestors (Just w) = getParent w >>= go (w:ancestors)



-- | === Excisability
-- Psuedocode from paper:
--   INPUTS: looping node, looping tree
--   COLLECT all ancestors of the looping node from the looping tree, ordered by
--           increasing depth (depth 0, or "root node," first)
--   FOR each ancestor
--     IF ancestor's distribution == looping node's distribution
--     THEN
--       the node is excisable: create loop in the tree
--       ENDFOR (ie "break")
--     ELSE do nothing
--     ENDIF
--   ENDFOR
excisable :: (l -> Maybe l) -> (l -> Vector Integer) -> Double -> l -> Maybe l
excisable getParent getFrequency sig l =
  runIdentity $ excisableM (pure . getParent) (pure . getFrequency) sig l

excisableM :: forall l m . Monad m => (l -> m (Maybe l)) -> (l -> m (Vector Integer)) -> Double -> l -> m (Maybe l)
excisableM getParent getFrequency sig l = do
  as <- getAncestorsM getParent l
  lf <- getFrequency l
  go lf as
  where
    go :: Vector Integer -> [l] -> m (Maybe l)
    go _     [] = pure Nothing
    go f (a:as) = do
      af <- getFrequency a
      case Prob.matchesFreqsAsDists sig f af of
        Significant    -> pure (Just a)
        NotSignificant -> go f as

showLeaf
  :: (l -> (Bool, [Vector Event]))
  -> (l -> [Vector Integer])
  -> (l -> [(Event, l)])
  -> Text
  -> Vector Event
  -> l
  -> String
showLeaf tohists todists tochilds pre st
  = runIdentity
  . showLeafM (pure . tohists) (pure . todists) (pure . tochilds) pre st

showLeafM
  :: forall l m . Monad m
  => (l -> m (Bool, [Vector Event]))
  -> (l -> m [Vector Integer])
  -> (l -> m [(Event, l)])
  -> Text
  -> Vector Event
  -> l
  -> m String
showLeafM tohists todists tochilds pre st l = T.unpack <$> go 0 (T.concat $ V.toList st) l
 where
  indent :: Int -> Text
  indent d = T.replicate (5 * d) " "

  go :: Int -> Event -> l -> m Text
  go d e l = do
    cs' <- tochilds l
    hs <- tohists l
    fs <- todists l
    case cs' of
      [] -> pure $ showNode d e hs fs <> ", no children}"
      cs -> do
        tcs <- mapM (uncurry $ go (d+1)) cs
        pure . T.concat $
          [ showNode d e hs fs <> "}\n"
          , indent (d + 1) <> "children:"
          , T.intercalate "\n" tcs
          ]

  showNode :: Int -> Event -> (Bool, [Vector Event]) -> [Vector Integer] -> Text
  showNode d e (isloop, hs) fs = T.concat
    [ "\n", indent d
    , T.pack (show e), "->", pre <> "Leaf{"
    , if isloop then "Loop(" else "", "obs: ", showList T.concat hs, if isloop then ")" else ""
    , if isloop then ""      else ", freq: " <> showList (num2txt show) fs
    , if isloop then ""      else ", dist: " <> showList (num2txt f'4) (fmap Prob.freqToDist fs)
    ]

  showList :: ([a] -> Text) -> [Vector a] -> Text
  showList shower as = "[" <> T.intercalate "," (fmap (shower . V.toList) as) <> "]"

  num2txt :: (n -> String) -> [n] -> Text
  num2txt showone = T.intercalate "," . fmap (T.pack . showone)


