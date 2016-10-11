{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DefaultSignatures   #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

-- |
-- Module      : Data.Binary.Serialise.CBOR.Class
-- Copyright   : (c) Duncan Coutts 2015
-- License     : BSD3-style (see LICENSE.txt)
--
-- Maintainer  : duncan@community.haskell.org
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--
-- The @'Serialise'@ class allows you to encode a given type into a
-- CBOR object, or decode a CBOR object into the user-specified type.
--
module Data.Binary.Serialise.CBOR.Class
 ( -- * The Serialise class
   Serialise(..)
 , GSerialiseEncode(..)
 , GSerialiseDecode(..)
 , encodeVector
 , decodeVector
 ) where

#include "cbor.h"

import           Control.Applicative

import           Control.Monad
import           Data.Hashable
import           Data.Int
import           Data.Monoid
import           Data.Proxy
import           Data.Version
import           Data.Word
import           Data.Complex
import           Data.Fixed
import           Data.Ratio
import           Data.Ord

#if MIN_VERSION_base(4,8,0)
import           Data.Functor.Identity
#endif

#if MIN_VERSION_base(4,9,0)
import qualified Data.Semigroup                      as Semigroup
#endif

import qualified Data.Foldable                       as Foldable
import qualified Data.ByteString                     as BS
import qualified Data.Text                           as Text

-- TODO FIXME: more instances
--import qualified Data.Array                          as Array
--import qualified Data.Array.Unboxed                  as UArray
import qualified Data.ByteString.Lazy                as BS.Lazy
import qualified Data.Map                            as Map
import qualified Data.Sequence                       as Sequence
import qualified Data.Set                            as Set
import qualified Data.IntSet                         as IntSet
import qualified Data.IntMap                         as IntMap
import qualified Data.HashSet                        as HashSet
import qualified Data.HashMap.Strict                 as HashMap
import qualified Data.Vector                         as Vector
import qualified Data.Vector.Unboxed                 as Vector.Unboxed
import qualified Data.Vector.Storable                as Vector.Storable
import qualified Data.Vector.Primitive               as Vector.Primitive
import qualified Data.Vector.Generic                 as Vector.Generic
import qualified Data.Text.Lazy                      as Text.Lazy
import           Foreign.C.Types

import           Data.Time                           (UTCTime (..), addUTCTime)
import           Data.Time.Calendar                  (fromGregorian)
#if MIN_VERSION_time(1,5,0)
import           Data.Time.Format                    (defaultTimeLocale,
                                                      formatTime, parseTimeM)
#else
import           Data.Time.Format                    (formatTime, parseTime)
import           System.Locale                       (defaultTimeLocale)
#endif
import           System.Exit                         (ExitCode(..))

import           Prelude hiding (decodeFloat, encodeFloat, foldr)
import qualified Prelude
import           Data.Typeable.Internal
import           GHC.Generics

import           Data.Binary.Serialise.CBOR.Decoding
import           Data.Binary.Serialise.CBOR.Encoding


--------------------------------------------------------------------------------
-- The Serialise class

-- | Types that are instances of the @'Serialise'@ class allow values
-- to be quickly encoded or decoded directly to a CBOR representation,
-- for object transmission or storage.
--
-- @since 0.2.0.0
class Serialise a where
    -- | Definition for encoding a given type into a binary
    -- representation, using the @'Encoding'@ @'Monoid'@.
    --
    -- @since 0.2.0.0
    encode  :: a -> Encoding
    default encode :: (Generic a, GSerialiseEncode (Rep a)) => a -> Encoding
    encode = gencode . from

    -- | Definition of a given @'Decoder'@ for a type.
    --
    -- @since 0.2.0.0
    decode  :: Decoder s a
    default decode :: (Generic a, GSerialiseDecode (Rep a)) => Decoder s a
    decode = to <$> gdecode

    -- | Utility to support specialised encoding for some list type -
    -- used for @'Char'@/@'String'@ instances in this package.
    --
    -- @since 0.2.0.0
    encodeList :: [a] -> Encoding
    encodeList = defaultEncodeList

    -- | Utility to support specialised decoding for some list type -
    -- used for @'Char'@/@'String'@ instances in this package.
    --
    -- @since 0.2.0.0
    decodeList :: Decoder s [a]
    decodeList = defaultDecodeList

--------------------------------------------------------------------------------
-- Special list business

-- | @since 0.2.0.0
instance Serialise a => Serialise [a] where
    encode = encodeList
    decode = decodeList

-- | Default @'Encoding'@ for list types.
--
-- @since 0.2.0.0
defaultEncodeList :: Serialise a => [a] -> Encoding
defaultEncodeList [] = encodeListLen 0
defaultEncodeList xs = encodeListLenIndef
                    <> Prelude.foldr (\x r -> encode x <> r) encodeBreak xs

-- | Default @'Decoder'@ for list types.
--
-- @since 0.2.0.0
defaultDecodeList :: Serialise a => Decoder s [a]
defaultDecodeList = do
    mn <- decodeListLenOrIndef
    case mn of
      Nothing -> decodeSequenceLenIndef (flip (:)) [] reverse   decode
      Just n  -> decodeSequenceLenN     (flip (:)) [] reverse n decode


--------------------------------------------------------------------------------
-- Primitive and integral instances

-- | @since 0.2.0.0
instance Serialise () where
    encode = const encodeNull
    decode = decodeNull

-- | @since 0.2.0.0
instance Serialise Bool where
    encode = encodeBool
    decode = decodeBool

-- | @since 0.2.0.0
instance Serialise Int where
    encode = encodeInt
    decode = decodeInt

-- | @since 0.2.0.0
instance Serialise Int8 where
    encode = encodeInt8
    decode = decodeInt8

-- | @since 0.2.0.0
instance Serialise Int16 where
    encode = encodeInt16
    decode = decodeInt16

-- | @since 0.2.0.0
instance Serialise Int32 where
    encode = encodeInt32
    decode = decodeInt32

-- | @since 0.2.0.0
instance Serialise Int64 where
    encode = encodeInt64
    decode = decodeInt64

-- | @since 0.2.0.0
instance Serialise Word where
    encode = encodeWord
    decode = decodeWord

-- | @since 0.2.0.0
instance Serialise Word8 where
    encode = encodeWord8
    decode = decodeWord8

-- | @since 0.2.0.0
instance Serialise Word16 where
    encode = encodeWord16
    decode = decodeWord16

-- | @since 0.2.0.0
instance Serialise Word32 where
    encode = encodeWord32
    decode = decodeWord32

-- | @since 0.2.0.0
instance Serialise Word64 where
    encode = encodeWord64
    decode = decodeWord64

-- | @since 0.2.0.0
instance Serialise Integer where
    encode = encodeInteger
    decode = decodeInteger

-- | @since 0.2.0.0
instance Serialise Float where
    encode = encodeFloat
    decode = decodeFloat

-- | @since 0.2.0.0
instance Serialise Double where
    encode = encodeDouble
    decode = decodeDouble

--------------------------------------------------------------------------------
-- Core types

#if MIN_VERSION_base(4,7,0)
-- | Values are serialised in units of least precision represented as
--   @Integer@.
--
-- @since 0.2.0.0
instance Serialise (Fixed e) where
    encode (MkFixed i) = encode i
    decode = MkFixed <$> decode

-- | @since 0.2.0.0
instance Serialise (Proxy a) where
    encode _ = encodeNull
    decode   = Proxy <$ decodeNull
#endif

-- | @since 0.2.0.0
instance Serialise Char where
    encode c = encodeString (Text.singleton c)
    decode = do t <- decodeString
                if Text.length t == 1
                  then return $! Text.head t
                  else fail "expected a single char, found a string"

    -- For [Char]/String we have a special encoding
    encodeList cs = encodeString (Text.pack cs)
    decodeList    = do txt <- decodeString
                       return (Text.unpack txt) -- unpack lazily

-- | @since 0.2.0.0
instance Serialise Text.Text where
    encode = encodeString
    decode = decodeString

-- | @since 0.2.0.0
instance Serialise BS.ByteString where
    encode = encodeBytes
    decode = decodeBytes

encodeChunked :: Serialise c
              => Encoding
              -> ((c -> Encoding -> Encoding) -> Encoding -> a -> Encoding)
              -> a
              -> Encoding
encodeChunked encodeIndef foldrChunks a =
    encodeIndef
 <> foldrChunks (\x r -> encode x <> r) encodeBreak a

decodeChunked :: Serialise c => Decoder s () -> ([c] -> a) -> Decoder s a
decodeChunked decodeIndef fromChunks = do
  decodeIndef
  decodeSequenceLenIndef (flip (:)) [] (fromChunks . reverse) decode

-- | @since 0.2.0.0
instance Serialise Text.Lazy.Text where
    encode = encodeChunked encodeStringIndef Text.Lazy.foldrChunks
    decode = decodeChunked decodeStringIndef Text.Lazy.fromChunks

-- | @since 0.2.0.0
instance Serialise BS.Lazy.ByteString where
    encode = encodeChunked encodeBytesIndef BS.Lazy.foldrChunks
    decode = decodeChunked decodeBytesIndef BS.Lazy.fromChunks

-- | @since 0.2.0.0
instance Serialise a => Serialise (Const a b) where
    encode (Const a) = encode a
    decode = Const <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (ZipList a) where
    encode (ZipList xs) = encode xs
    decode = ZipList <$> decode

-- | @since 0.2.0.0
instance (Serialise a, Integral a) => Serialise (Ratio a) where
    encode a = encodeListLen 2
            <> encode (numerator a)
            <> encode (denominator a)
    decode = do decodeListLenOf 2
                !a <- decode
                !b <- decode
                return $ a % b

-- | @since 0.2.0.0
instance Serialise a => Serialise (Complex a) where
    encode (r :+ i) = encodeListLen 2
                   <> encode r
                   <> encode i
    decode = do decodeListLenOf 2
                !r <- decode
                !i <- decode
                return $ r :+ i

-- | @since 0.2.0.0
instance Serialise Ordering where
    encode a = encodeListLen 1
            <> encodeWord (case a of LT -> 0
                                     EQ -> 1
                                     GT -> 2)
    decode = do
      decodeListLenOf 1
      t <- decodeWord
      case t of
        0 -> return LT
        1 -> return EQ
        2 -> return GT
        _ -> fail "unexpected tag"

-- | @since 0.2.0.0
instance Serialise a => Serialise (Down a) where
    encode (Down a) = encode a
    decode = Down <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Dual a) where
    encode (Dual a) = encode a
    decode = Dual <$> decode

-- | @since 0.2.0.0
instance Serialise All where
    encode (All b) = encode b
    decode = All <$> decode

-- | @since 0.2.0.0
instance Serialise Any where
    encode (Any b) = encode b
    decode = Any <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Sum a) where
    encode (Sum b) = encode b
    decode = Sum <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Product a) where
    encode (Product b) = encode b
    decode = Product <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (First a) where
    encode (First b) = encode b
    decode = First <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Last a) where
    encode (Last b) = encode b
    decode = Last <$> decode

#if MIN_VERSION_base(4,8,0)
-- | @since 0.2.0.0
instance Serialise (f a) => Serialise (Alt f a) where
    encode (Alt b) = encode b
    decode = Alt <$> decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Identity a) where
    encode (Identity b) = encode b
    decode = Identity <$> decode
#endif

-- | @since 0.2.0.0
instance Serialise ExitCode where
    encode ExitSuccess     = encodeListLen 1
                          <> encodeWord 0
    encode (ExitFailure i) = encodeListLen 2
                          <> encodeWord 1
                          <> encode i
    decode = do
      n <- decodeListLen
      case n of
        1 -> do t <- decodeWord
                case t of
                  0 -> return ExitSuccess
                  _ -> fail "unexpected tag"
        2 -> do t <- decodeWord
                case t of
                  1 -> return ()
                  _ -> fail "unexpected tag"
                !i <- decode
                return $ ExitFailure i
        _ -> fail "Bad list length"

-- Semigroup instances for GHC 8.0+
#if MIN_VERSION_base(4,9,0)
-- | @since 0.2.0.0
instance Serialise a => Serialise (Semigroup.Min a) where
  encode = encode . Semigroup.getMin
  decode = fmap Semigroup.Min decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Semigroup.Max a) where
  encode = encode . Semigroup.getMax
  decode = fmap Semigroup.Max decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Semigroup.First a) where
  encode = encode . Semigroup.getFirst
  decode = fmap Semigroup.First decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Semigroup.Last a) where
  encode = encode . Semigroup.getLast
  decode = fmap Semigroup.Last decode

-- | @since 0.2.0.0
instance Serialise a => Serialise (Semigroup.Option a) where
  encode = encode . Semigroup.getOption
  decode = fmap Semigroup.Option decode
#endif

--------------------------------------------------------------------------------
-- Foreign types

-- | @since 0.2.0.0
instance Serialise CChar where
    encode (CChar x) = encode x
    decode = CChar <$> decode

-- | @since 0.2.0.0
instance Serialise CSChar where
    encode (CSChar x) = encode x
    decode = CSChar <$> decode

-- | @since 0.2.0.0
instance Serialise CUChar where
    encode (CUChar x) = encode x
    decode = CUChar <$> decode

-- | @since 0.2.0.0
instance Serialise CShort where
    encode (CShort x) = encode x
    decode = CShort <$> decode

-- | @since 0.2.0.0
instance Serialise CUShort where
    encode (CUShort x) = encode x
    decode = CUShort <$> decode

-- | @since 0.2.0.0
instance Serialise CInt where
    encode (CInt x) = encode x
    decode = CInt <$> decode

-- | @since 0.2.0.0
instance Serialise CUInt where
    encode (CUInt x) = encode x
    decode = CUInt <$> decode

-- | @since 0.2.0.0
instance Serialise CLong where
    encode (CLong x) = encode x
    decode = CLong <$> decode

-- | @since 0.2.0.0
instance Serialise CULong where
    encode (CULong x) = encode x
    decode = CULong <$> decode

-- | @since 0.2.0.0
instance Serialise CPtrdiff where
    encode (CPtrdiff x) = encode x
    decode = CPtrdiff <$> decode

-- | @since 0.2.0.0
instance Serialise CSize where
    encode (CSize x) = encode x
    decode = CSize <$> decode

-- | @since 0.2.0.0
instance Serialise CWchar where
    encode (CWchar x) = encode x
    decode = CWchar <$> decode

-- | @since 0.2.0.0
instance Serialise CSigAtomic where
    encode (CSigAtomic x) = encode x
    decode = CSigAtomic <$> decode

-- | @since 0.2.0.0
instance Serialise CLLong where
    encode (CLLong x) = encode x
    decode = CLLong <$> decode

-- | @since 0.2.0.0
instance Serialise CULLong where
    encode (CULLong x) = encode x
    decode = CULLong <$> decode

-- | @since 0.2.0.0
instance Serialise CIntPtr where
    encode (CIntPtr x) = encode x
    decode = CIntPtr <$> decode

-- | @since 0.2.0.0
instance Serialise CUIntPtr where
    encode (CUIntPtr x) = encode x
    decode = CUIntPtr <$> decode

-- | @since 0.2.0.0
instance Serialise CIntMax where
    encode (CIntMax x) = encode x
    decode = CIntMax <$> decode

-- | @since 0.2.0.0
instance Serialise CUIntMax where
    encode (CUIntMax x) = encode x
    decode = CUIntMax <$> decode

-- | @since 0.2.0.0
instance Serialise CClock where
    encode (CClock x) = encode x
    decode = CClock <$> decode

-- | @since 0.2.0.0
instance Serialise CTime where
    encode (CTime x) = encode x
    decode = CTime <$> decode

-- | @since 0.2.0.0
instance Serialise CUSeconds where
    encode (CUSeconds x) = encode x
    decode = CUSeconds <$> decode

-- | @since 0.2.0.0
instance Serialise CSUSeconds where
    encode (CSUSeconds x) = encode x
    decode = CSUSeconds <$> decode

-- | @since 0.2.0.0
instance Serialise CFloat where
    encode (CFloat x) = encode x
    decode = CFloat <$> decode

-- | @since 0.2.0.0
instance Serialise CDouble where
    encode (CDouble x) = encode x
    decode = CDouble <$> decode

--------------------------------------------------------------------------------
-- Structural instances

-- | @since 0.2.0.0
instance (Serialise a, Serialise b) => Serialise (a,b) where
    encode (a,b) = encodeListLen 2
                <> encode a
                <> encode b
    decode = do decodeListLenOf 2
                !x <- decode
                !y <- decode
                return (x, y)

-- | @since 0.2.0.0
instance (Serialise a, Serialise b, Serialise c) => Serialise (a,b,c) where
    encode (a,b,c) = encodeListLen 3
                  <> encode a
                  <> encode b
                  <> encode c

    decode = do decodeListLenOf 3
                !x <- decode
                !y <- decode
                !z <- decode
                return (x, y, z)

-- | @since 0.2.0.0
instance (Serialise a, Serialise b, Serialise c, Serialise d
         ) => Serialise (a,b,c,d) where
    encode (a,b,c,d) = encodeListLen 4
                    <> encode a
                    <> encode b
                    <> encode c
                    <> encode d

    decode = do decodeListLenOf 4
                !a <- decode
                !b <- decode
                !c <- decode
                !d <- decode
                return (a, b, c, d)

-- | @since 0.2.0.0
instance (Serialise a, Serialise b, Serialise c, Serialise d, Serialise e
         ) => Serialise (a,b,c,d,e) where
    encode (a,b,c,d,e) = encodeListLen 5
                      <> encode a
                      <> encode b
                      <> encode c
                      <> encode d
                      <> encode e

    decode = do decodeListLenOf 5
                !a <- decode
                !b <- decode
                !c <- decode
                !d <- decode
                !e <- decode
                return (a, b, c, d, e)

-- | @since 0.2.0.0
instance ( Serialise a, Serialise b, Serialise c, Serialise d, Serialise e
         , Serialise f
         ) => Serialise (a,b,c,d,e,f) where
    encode (a,b,c,d,e,f) = encodeListLen 6
                        <> encode a
                        <> encode b
                        <> encode c
                        <> encode d
                        <> encode e
                        <> encode f

    decode = do decodeListLenOf 6
                !a <- decode
                !b <- decode
                !c <- decode
                !d <- decode
                !e <- decode
                !f <- decode
                return (a, b, c, d, e, f)

-- | @since 0.2.0.0
instance ( Serialise a, Serialise b, Serialise c, Serialise d, Serialise e
         , Serialise f, Serialise g
         ) => Serialise (a,b,c,d,e,f,g) where
    encode (a,b,c,d,e,f,g) = encodeListLen 7
                          <> encode a
                          <> encode b
                          <> encode c
                          <> encode d
                          <> encode e
                          <> encode f
                          <> encode g

    decode = do decodeListLenOf 7
                !a <- decode
                !b <- decode
                !c <- decode
                !d <- decode
                !e <- decode
                !f <- decode
                !g <- decode
                return (a, b, c, d, e, f, g)

-- | @since 0.2.0.0
instance Serialise a => Serialise (Maybe a) where
    encode Nothing  = encodeListLen 0
    encode (Just x) = encodeListLen 1 <> encode x

    decode = do n <- decodeListLen
                case n of
                  0 -> return Nothing
                  1 -> do !x <- decode
                          return (Just x)
                  _ -> fail "unknown tag"

-- | @since 0.2.0.0
instance (Serialise a, Serialise b) => Serialise (Either a b) where
    encode (Left  x) = encodeListLen 2 <> encodeWord 0 <> encode x
    encode (Right x) = encodeListLen 2 <> encodeWord 1 <> encode x

    decode = do decodeListLenOf 2
                t <- decodeWord
                case t of
                  0 -> do !x <- decode
                          return (Left x)
                  1 -> do !x <- decode
                          return (Right x)
                  _ -> fail "unknown tag"


--------------------------------------------------------------------------------
-- Container instances

encodeContainerSkel :: (Word -> Encoding)
                    -> (container -> Int)
                    -> (accumFunc -> Encoding -> container -> Encoding)
                    -> accumFunc
                    -> container
                    -> Encoding
encodeContainerSkel encodeLen size foldr f  c =
    encodeLen (fromIntegral (size c)) <> foldr f mempty c
{-# INLINE encodeContainerSkel #-}

decodeContainerSkelWithReplicate
  :: (Serialise a)
  => Decoder s Int
     -- ^ How to get the size of the container
  -> (Int -> Decoder s a -> Decoder s container)
     -- ^ replicateM for the container
  -> ([container] -> container)
     -- ^ concat for the container
  -> Decoder s container
decodeContainerSkelWithReplicate decodeLen replicateFun fromList = do
    -- Look at how much data we have at the moment and use it as the limit for
    -- the size of a single call to replicateFun. We don't want to use
    -- replicateFun directly on the result of decodeLen since this might lead to
    -- DOS attack (attacker providing a huge value for length). So if it's above
    -- our limit, we'll do manual chunking and then combine the containers into
    -- one.
    size <- decodeLen
    limit <- peekAvailable
    if size <= limit
       then replicateFun size decode
       else do
           -- Take the max of limit and a fixed chunk size (note: limit can be
           -- 0). This basically means that the attacker can make us allocate a
           -- container of size 128 even though there's no actual input.
           let chunkSize = max limit 128
               (d, m) = size `divMod` chunkSize
               buildOne s = replicateFun s decode
           containers <- sequence $ buildOne m : replicate d (buildOne chunkSize)
           return $! fromList containers
{-# INLINE decodeContainerSkelWithReplicate #-}

-- | @since 0.2.0.0
instance (Serialise a) => Serialise (Sequence.Seq a) where
  encode = encodeContainerSkel
             encodeListLen
             Sequence.length
             Foldable.foldr
             (\a b -> encode a <> b)
  decode = decodeContainerSkelWithReplicate
             decodeListLen
             Sequence.replicateM
             mconcat

-- | Generic encoder for vectors. Its intended use is to allow easy
-- definition of 'Serialise' instances for custom vector
--
-- @since 0.2.0.0
encodeVector :: (Serialise a, Vector.Generic.Vector v a)
             => v a -> Encoding
encodeVector = encodeContainerSkel
    encodeListLen
    Vector.Generic.length
    Vector.Generic.foldr
    (\a b -> encode a <> b)
{-# INLINE encodeVector #-}

-- | Generic decoder for vectors. Its intended use is to allow easy
-- definition of 'Serialise' instances for custom vector
--
-- @since 0.2.0.0
decodeVector :: (Serialise a, Vector.Generic.Vector v a)
             => Decoder s (v a)
decodeVector = decodeContainerSkelWithReplicate
    decodeListLen
    Vector.Generic.replicateM
    Vector.Generic.concat
{-# INLINE decodeVector #-}

-- | @since 0.2.0.0
instance (Serialise a) => Serialise (Vector.Vector a) where
  encode = encodeVector
  {-# INLINE encode #-}
  decode = decodeVector
  {-# INLINE decode #-}

-- | @since 0.2.0.0
instance (Serialise a, Vector.Unboxed.Unbox a) =>
         Serialise (Vector.Unboxed.Vector a) where
  encode = encodeVector
  {-# INLINE encode #-}
  decode = decodeVector
  {-# INLINE decode #-}

-- | @since 0.2.0.0
instance (Serialise a, Vector.Storable.Storable a) => Serialise (Vector.Storable.Vector a) where
  encode = encodeVector
  {-# INLINE encode #-}
  decode = decodeVector
  {-# INLINE decode #-}

-- | @since 0.2.0.0
instance (Serialise a, Vector.Primitive.Prim a) => Serialise (Vector.Primitive.Vector a) where
  encode = encodeVector
  {-# INLINE encode #-}
  decode = decodeVector
  {-# INLINE decode #-}



encodeSetSkel :: Serialise a
              => (s -> Int)
              -> ((a -> Encoding -> Encoding) -> Encoding -> s -> Encoding)
              -> s
              -> Encoding
encodeSetSkel size foldr =
    encodeContainerSkel encodeListLen size foldr (\a b -> encode a <> b)
{-# INLINE encodeSetSkel #-}

decodeSetSkel :: Serialise a
              => ([a] -> c) -> Decoder s c
decodeSetSkel fromList = do
  n <- decodeListLen
  fmap fromList (replicateM n decode)
{-# INLINE decodeSetSkel #-}

-- | @since 0.2.0.0
instance (Ord a, Serialise a) => Serialise (Set.Set a) where
  encode = encodeSetSkel Set.size Set.foldr
  decode = decodeSetSkel Set.fromList

-- | @since 0.2.0.0
instance Serialise IntSet.IntSet where
  encode = encodeSetSkel IntSet.size IntSet.foldr
  decode = decodeSetSkel IntSet.fromList

-- | @since 0.2.0.0
instance (Serialise a, Hashable a, Eq a) => Serialise (HashSet.HashSet a) where
  encode = encodeSetSkel HashSet.size HashSet.foldr
  decode = decodeSetSkel HashSet.fromList

encodeMapSkel :: (Serialise k, Serialise v)
              => (m -> Int)
              -> ((k -> v -> Encoding -> Encoding) -> Encoding -> m -> Encoding)
              -> m
              -> Encoding
encodeMapSkel size foldrWithKey =
  encodeContainerSkel
    encodeMapLen
    size
    foldrWithKey
    (\k v b -> encode k <> encode v <> b)
{-# INLINE encodeMapSkel #-}

decodeMapSkel :: (Serialise k, Serialise v)
              => ([(k,v)] -> m)
              -> Decoder s m
decodeMapSkel fromList = do
  n <- decodeMapLen
  let decodeEntry = do
        !k <- decode
        !v <- decode
        return (k, v)
  fmap fromList (replicateM n decodeEntry)
{-# INLINE decodeMapSkel #-}

-- | @since 0.2.0.0
instance (Ord k, Serialise k, Serialise v) => Serialise (Map.Map k v) where
  encode = encodeMapSkel Map.size Map.foldrWithKey
  decode = decodeMapSkel Map.fromList

-- | @since 0.2.0.0
instance (Serialise a) => Serialise (IntMap.IntMap a) where
  encode = encodeMapSkel IntMap.size IntMap.foldrWithKey
  decode = decodeMapSkel IntMap.fromList

-- | @since 0.2.0.0
instance (Serialise k, Hashable k, Eq k, Serialise v) =>
  Serialise (HashMap.HashMap k v) where
  encode = encodeMapSkel HashMap.size HashMap.foldrWithKey
  decode = decodeMapSkel HashMap.fromList


--------------------------------------------------------------------------------
-- Misc base package instances

-- | @since 0.2.0.0
instance Serialise Version where
    encode (Version ns ts) = encodeListLen 3
                          <> encodeWord 0 <> encode ns <> encode ts
    decode = do
      len <- decodeListLen
      tag <- decodeWord
      case tag of
        0 | len == 3
          -> do !x <- decode
                !y <- decode
                return (Version x y)
        _ -> fail "unexpected tag"

-- | @since 0.2.0.0
instance Serialise Fingerprint where
    encode (Fingerprint w1 w2) = encodeListLen 3
                              <> encodeWord 0
                              <> encode w1
                              <> encode w2
    decode = do
      decodeListLenOf 3
      tag <- decodeWord
      case tag of
        0 -> do !w1 <- decode
                !w2 <- decode
                return $! Fingerprint w1 w2
        _ -> fail "unexpected tag"

-- | @since 0.2.0.0
instance Serialise TyCon where
#if MIN_VERSION_base(4,9,0)
  encode tycon
    = encodeListLen 4
   <> encodeWord 0
   <> encode (tyConPackage tycon)
   <> encode (tyConModule  tycon)
   <> encode (tyConName    tycon)
#else
  encode (TyCon _ pkg modname name)
    = encodeListLen 4
   <> encodeWord 0
   <> encode pkg
   <> encode modname
   <> encode name
#endif

  decode = do
    decodeListLenOf 4
    tag <- decodeWord
    case tag of
      0 -> do !pkg     <- decode
              !modname <- decode
              !name    <- decode
              return $! mkTyCon3 pkg modname name
      _ -> fail "unexpected tag"

-- | @since 0.2.0.0
instance Serialise TypeRep where
#if MIN_VERSION_base(4,8,0)
  encode (TypeRep fp tycon kirep tyrep)
    = encodeListLen 5
   <> encodeWord 0
   <> encode fp
   <> encode tycon
   <> encode kirep
   <> encode tyrep

  decode = do
    decodeListLenOf 5
    tag <- decodeWord
    case tag of
      0 -> do !fp    <- decode
              !tycon <- decode
              !kirep <- decode
              !tyrep <- decode
              return $! TypeRep fp tycon kirep tyrep
      _ -> fail "unexpected tag"
#else
  encode (TypeRep fp tycon tyrep)
    = encodeListLen 4
   <> encodeWord 0
   <> encode fp
   <> encode tycon
   <> encode tyrep

  decode = do
    decodeListLenOf 4
    tag <- decodeWord
    case tag of
      0 -> do !fp    <- decode
              !tycon <- decode
              !tyrep <- decode
              return $! TypeRep fp tycon tyrep
      _ -> fail "unexpected tag"
#endif

--------------------------------------------------------------------------------
-- Time instances
--
-- CBOR has some special encodings for times/timestamps

-- | @since 0.2.0.0
instance Serialise UTCTime where
    encode d = encodeTag 0
            <> encode (formatUTCrfc3339 d)

    decode = do
      tag <- decodeTag
      case tag of
        0 -> do str <- decodeString
                case parseUTCrfc3339 (Text.unpack str) of
                  Just t  -> return $! forceUTCTime t
                  Nothing -> fail "Could not parse RFC3339 date"
        1 -> do
          tt <- peekTokenType
          case tt of
            TypeUInt    -> utcFromIntegral <$> decodeWord
            TypeUInt64  -> utcFromIntegral <$> decodeWord64
            TypeNInt    -> utcFromIntegral <$> decodeInt
            TypeNInt64  -> utcFromIntegral <$> decodeInt64
            TypeInteger -> utcFromIntegral <$> decodeInteger
            TypeFloat16 -> utcFromReal <$> decodeFloat
            TypeFloat32 -> utcFromReal <$> decodeFloat
            TypeFloat64 -> utcFromReal <$> decodeDouble
            _ -> fail "Expected numeric type following tag 1 (epoch offset)"
        _ -> fail "Expected timestamp (tag 0 or 1)"

epoch :: UTCTime
epoch = UTCTime (fromGregorian 1970 1 1) 0

{-# INLINE utcFromIntegral #-}
utcFromIntegral :: Integral a => a -> UTCTime
utcFromIntegral i = addUTCTime (fromIntegral i) epoch

{-# INLINE utcFromReal #-}
utcFromReal :: Real a => a -> UTCTime
utcFromReal f = addUTCTime (fromRational (toRational f)) epoch


-- | @'UTCTime'@ formatting, into a regular @'String'@.
formatUTCrfc3339 :: UTCTime -> String

-- | @'UTCTime'@ parsing, from a regular @'String'@.
parseUTCrfc3339  :: String -> Maybe UTCTime

-- Format UTC as timezone 'Z', but on parsing accept 'Z' or any numeric offset
formatUTCrfc3339 = formatTime       defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"
#if MIN_VERSION_time(1,5,0)
parseUTCrfc3339  = parseTimeM False defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Q%Z"
#else
parseUTCrfc3339  = parseTime        defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Q%Z"
#endif

-- | Force the unnecessarily lazy @'UTCTime'@ representation.
forceUTCTime :: UTCTime -> UTCTime
forceUTCTime t@(UTCTime !_day !_daytime) = t


--------------------------------------------------------------------------------
-- Generic instances

-- Factored into two classes because this makes GHC optimize the
-- instances faster. This doesn't matter for builds of binary, but it
-- matters a lot for end-users who write 'instance Binary T'. See
-- also: https://ghc.haskell.org/trac/ghc/ticket/9630

-- | @since 0.2.0.0
class GSerialiseEncode f where
    -- | @since 0.2.0.0
    gencode  :: f a -> Encoding

-- | @since 0.2.0.0
class GSerialiseDecode f where
    -- | @since 0.2.0.0
    gdecode  :: Decoder s (f a)

-- | @since 0.2.0.0
instance GSerialiseEncode V1 where
    -- Data types without constructors are still serialised as null value
    gencode _ = encodeNull

-- | @since 0.2.0.0
instance GSerialiseDecode V1 where
    gdecode   = error "V1 don't have contructors" <$ decodeNull

-- | @since 0.2.0.0
instance GSerialiseEncode U1 where
    -- Constructors without fields are serialised as null value
    gencode _ = encodeListLen 1 <> encodeWord 0

-- | @since 0.2.0.0
instance GSerialiseDecode U1 where
    gdecode   = do
      n <- decodeListLen
      when (n /= 1) $ fail "expect list of length 1"
      tag <- decodeWord
      when (tag /= 0) $ fail "unexpected tag. Expect 0"
      return U1

-- | @since 0.2.0.0
instance GSerialiseEncode a => GSerialiseEncode (M1 i c a) where
    -- Metadata (constructor name, etc) is skipped
    gencode = gencode . unM1

-- | @since 0.2.0.0
instance GSerialiseDecode a => GSerialiseDecode (M1 i c a) where
    gdecode = M1 <$> gdecode

-- | @since 0.2.0.0
instance Serialise a => GSerialiseEncode (K1 i a) where
    -- Constructor field (Could only appear in one-field & one-constructor
    -- data types). In all other cases we go through GSerialise{Sum,Prod}
    gencode (K1 a) = encodeListLen 2
                  <> encodeWord 0
                  <> encode a

-- | @since 0.2.0.0
instance Serialise a => GSerialiseDecode (K1 i a) where
    gdecode = do
      n <- decodeListLen
      when (n /= 2) $
        fail "expect list of length 2"
      tag <- decodeWord
      when (tag /= 0) $
        fail "unexpected tag. Expects 0"
      K1 <$> decode

-- | @since 0.2.0.0
instance (GSerialiseProd f, GSerialiseProd g) => GSerialiseEncode (f :*: g) where
    -- Products are serialised as N-tuples with 0 constructor tag
    gencode (f :*: g)
        = encodeListLen (nFields (Proxy :: Proxy (f :*: g)) + 1)
       <> encodeWord 0
       <> encodeSeq f
       <> encodeSeq g

-- | @since 0.2.0.0
instance (GSerialiseProd f, GSerialiseProd g) => GSerialiseDecode (f :*: g) where
    gdecode = do
      let nF = nFields (Proxy :: Proxy (f :*: g))
      n <- decodeListLen
      -- TODO FIXME: signedness of list length
      when (fromIntegral n /= nF + 1) $
        fail $ "Wrong number of fields: expected="++show (nF+1)++" got="++show n
      tag <- decodeWord
      when (tag /= 0) $
        fail $ "unexpect tag (expect 0)"
      !f <- gdecodeSeq
      !g <- gdecodeSeq
      return $ f :*: g

-- | @since 0.2.0.0
instance (GSerialiseSum f, GSerialiseSum g) => GSerialiseEncode (f :+: g) where
    -- Sum types are serialised as N-tuples and first element is
    -- constructor tag
    gencode a = encodeListLen (numOfFields a + 1)
             <> encode (conNumber a)
             <> encodeSum a

-- | @since 0.2.0.0
instance (GSerialiseSum f, GSerialiseSum g) => GSerialiseDecode (f :+: g) where
    gdecode = do
        n <- decodeListLen
        -- TODO FIXME: Again signedness
        when (n == 0) $
          fail "Empty list encountered for sum type"
        nCon  <- decodeWord
        trueN <- fieldsForCon (Proxy :: Proxy (f :+: g)) nCon
        when (n-1 /= fromIntegral trueN ) $
          fail $ "Number of fields mismatch: expected="++show trueN++" got="++show n
        decodeSum nCon


-- | Serialization of product types
class GSerialiseProd f where
    -- | Number of fields in product type
    nFields   :: Proxy f -> Word
    -- | Encode fields sequentially without writing header
    encodeSeq :: f a -> Encoding
    -- | Decode fields sequentially without reading header
    gdecodeSeq :: Decoder s (f a)

-- | @since 0.2.0.0
instance (GSerialiseProd f, GSerialiseProd g) => GSerialiseProd (f :*: g) where
    nFields _ = nFields (Proxy :: Proxy f) + nFields (Proxy :: Proxy g)
    encodeSeq (f :*: g) = encodeSeq f <> encodeSeq g
    gdecodeSeq = do !f <- gdecodeSeq
                    !g <- gdecodeSeq
                    return (f :*: g)

-- | @since 0.2.0.0
instance GSerialiseProd U1 where
    -- N.B. Could only be reached when one of constructors in sum type
    --      don't have parameters
    nFields   _ = 0
    encodeSeq _ = mempty
    gdecodeSeq  = return U1

-- | @since 0.2.0.0
instance (Serialise a) => GSerialiseProd (K1 i a) where
    -- Ordinary field
    nFields    _     = 1
    encodeSeq (K1 f) = encode f
    gdecodeSeq       = K1 <$> decode

-- | @since 0.2.0.0
instance (i ~ S, GSerialiseProd f) => GSerialiseProd (M1 i c f) where
    -- We skip metadata
    nFields     _     = 1
    encodeSeq  (M1 f) = encodeSeq f
    gdecodeSeq        = M1 <$> gdecodeSeq


-- | Serialization of sum types
--
-- @since 0.2.0.0
class GSerialiseSum f where
    -- | Number of constructor of given value
    conNumber   :: f a -> Word
    -- | Number of fields of given value
    numOfFields :: f a -> Word
    -- | Encode field
    encodeSum   :: f a  -> Encoding

    -- | Decode field
    decodeSum     :: Word -> Decoder s (f a)
    -- | Number of constructors
    nConstructors :: Proxy f -> Word
    -- | Number of fields for given constructor number
    fieldsForCon  :: Proxy f -> Word -> Decoder s Word


-- | @since 0.2.0.0
instance (GSerialiseSum f, GSerialiseSum g) => GSerialiseSum (f :+: g) where
    conNumber x = case x of
      L1 f -> conNumber f
      R1 g -> conNumber g + nConstructors (Proxy :: Proxy f)
    numOfFields x = case x of
      L1 f -> numOfFields f
      R1 g -> numOfFields g
    encodeSum x = case x of
      L1 f -> encodeSum f
      R1 g -> encodeSum g

    nConstructors _ = nConstructors (Proxy :: Proxy f)
                    + nConstructors (Proxy :: Proxy g)

    fieldsForCon _ n | n < nL    = fieldsForCon (Proxy :: Proxy f) n
                     | otherwise = fieldsForCon (Proxy :: Proxy g) (n - nL)
      where
        nL = nConstructors (Proxy :: Proxy f)

    decodeSum nCon | nCon < nL = L1 <$> decodeSum nCon
                   | otherwise = R1 <$> decodeSum (nCon - nL)
      where
        nL = nConstructors (Proxy :: Proxy f)


-- | @since 0.2.0.0
instance (i ~ C, GSerialiseProd f) => GSerialiseSum (M1 i c f) where
    conNumber    _     = 0
    numOfFields  _     = nFields (Proxy :: Proxy f)
    encodeSum   (M1 f) = encodeSeq f

    nConstructors  _ = 1
    fieldsForCon _ 0 = return $ nFields (Proxy :: Proxy f)
    fieldsForCon _ _ = fail "Bad constructor number"
    decodeSum      0 = M1 <$> gdecodeSeq
    decodeSum      _ = fail "bad constructor number"
