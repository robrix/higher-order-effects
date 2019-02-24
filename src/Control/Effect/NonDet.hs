{-# LANGUAGE DeriveFunctor, FlexibleInstances, LambdaCase, MultiParamTypeClasses, TypeOperators, UndecidableInstances #-}
module Control.Effect.NonDet
( NonDet(..)
, Alternative(..)
, runNonDet
, AltC(..)
, runNonDetOnce
, OnceC(..)
, Branch(..)
, branch
, runBranch
) where

import Control.Applicative (Alternative(..), liftA2)
import Control.Effect.Carrier
import Control.Effect.Cull
import Control.Effect.Internal
import Control.Effect.NonDet.Internal
import Control.Effect.Sum
import Control.Monad.Fail
import Control.Monad.IO.Class
import Data.Monoid as Monoid (Alt(..))
import Prelude hiding (fail)

-- | Run a 'NonDet' effect, collecting all branches’ results into an 'Alternative' functor.
--
--   Using '[]' as the 'Alternative' functor will produce all results, while 'Maybe' will return only the first. However, unlike 'runNonDetOnce', this will still enumerate the entire search space before returning, meaning that it will diverge for infinite search spaces, even when using 'Maybe'.
--
--   prop> run (runNonDet (pure a)) == [a]
--   prop> run (runNonDet (pure a)) == Just a
runNonDet :: (Alternative f, Monad f, Traversable f, Carrier sig m, Effect sig, Applicative m) => Eff (AltC f m) a -> m (f a)
runNonDet = runAltC . interpret

newtype AltC f m a = AltC { runAltC :: m (f a) }
  deriving (Functor)

instance (Applicative f, Applicative m) => Applicative (AltC f m) where
  pure = AltC . pure . pure
  AltC f <*> AltC a = AltC (liftA2 (<*>) f a)

instance (Alternative f, Carrier sig m, Effect sig, Monad f, Traversable f, Applicative m) => Alternative (AltC f m) where
  empty = send Empty
  l <|> r = send (Choose (\ c -> if c then l else r))

instance (Alternative f, Carrier sig m, Effect sig, Monad f, Monad m, Traversable f) => Monad (AltC f m) where
  AltC a >>= f = AltC (a >>= runAltC . getAlt . foldMap (Monoid.Alt . f))

instance (Alternative f, Carrier sig m, Effect sig, Monad f, MonadFail m, Traversable f) => MonadFail (AltC f m) where
  fail s = AltC (fail s)

instance (Alternative f, Carrier sig m, Effect sig, Monad f, Traversable f, Applicative m) => Carrier (NonDet :+: sig) (AltC f m) where
  ret = pure
  eff = AltC . handleSum (eff . handleTraversable runAltC) (\case
    Empty    -> ret empty
    Choose k -> liftA2 (<|>) (runAltC (k True)) (runAltC (k False)))


-- | Run a 'NonDet' effect, returning the first successful result in an 'Alternative' functor.
--
--   Unlike 'runNonDet', this will terminate immediately upon finding a solution.
--
--   prop> run (runNonDetOnce (asum (map pure (repeat a)))) == [a]
--   prop> run (runNonDetOnce (asum (map pure (repeat a)))) == Just a
runNonDetOnce :: (Alternative f, Carrier sig m, Effect sig, Monad f, Monad m, Traversable f) => Eff (OnceC f m) a -> m (f a)
runNonDetOnce = runNonDet . runCull . cull . runOnceC . interpret

newtype OnceC f m a = OnceC { runOnceC :: Eff (CullC (Eff (AltC f m))) a }
  deriving (Functor)

instance (Alternative f, Carrier sig m, Effect sig, Monad f, Monad m, Traversable f) => Carrier (NonDet :+: sig) (OnceC f m) where
  ret = OnceC . ret
  eff = OnceC . handleSum (eff . R . R . R . handleCoercible) (\case
    Empty    -> empty
    Choose k -> runOnceC (k True) <|> runOnceC (k False))


-- $setup
-- >>> :seti -XFlexibleContexts
-- >>> import Test.QuickCheck
-- >>> import Control.Effect.Void
-- >>> import Data.Foldable (asum)
