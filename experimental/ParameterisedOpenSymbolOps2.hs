{- Parameterised open handlers with parameterised symbolic operations -}

{-# LANGUAGE TypeFamilies,
    MultiParamTypeClasses, FlexibleInstances, FlexibleContexts,
    TypeOperators, ScopedTypeVariables,
    NoMonomorphismRestriction,
    PolyKinds, DataKinds
  #-}

module ParameterisedOpenOps where

import GHC.TypeLits

type family Return (op :: *) :: *
type instance Return (Op name p r) = r

data family Op (name :: Symbol) (p :: *) (r :: *) :: *

class Handler h where
  type Result h :: *
  type Inner h :: *
  ret :: h -> Inner h -> Result h

class Handles h op where
  clause :: h -> op -> (h -> Return op -> Result h) -> Result h

data Comp h a = Comp {unComp :: h -> (h -> a -> Result h) -> Result h}

instance Monad (Comp h) where
  return v     = Comp (\h k -> k h v)
  Comp c >>= f = Comp (\h k -> c h (\h' x -> unComp (f x) h' k))

instance Functor (Comp h) where
  fmap f c = c >>= return . f

doOp :: (h `Handles` op) => op -> Comp h (Return op)
doOp op = Comp (\h k -> clause h op k)

handle :: (Handler h) => Comp h (Inner h) -> h -> Result h
handle (Comp c) h = c h ret

data instance Op "get" () s = Get
type Get s = Op "get" () s
get :: (h `Handles` Get s) => Comp h s
get = doOp Get

data instance Op "put" s () = Put s
type Put s = Op "put" s ()
put :: (h `Handles` Put s) => s -> Comp h ()
put s = doOp (Put s)

data StateHandler (s :: *) (a :: *) = StateHandler s
instance Handler (StateHandler s a) where
  type Result (StateHandler s a) = a
  type Inner (StateHandler s a)  = a
  ret _ x = x

instance (StateHandler s a `Handles` Put s) where
  clause _ (Put s) k = k (StateHandler s) ()

instance (StateHandler s a `Handles` Get s) where
  clause (StateHandler s) Get k = k (StateHandler s) s

--count :: (h `Handles` Get Int, h `Handles` Put Int) => Comp h ()
count =
    do
      n <- get;
      if n == (0 :: Int) then return ()
      else do {put (n-1); count}