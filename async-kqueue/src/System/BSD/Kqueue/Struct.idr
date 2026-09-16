module System.BSD.Kqueue.Struct

import Data.Bits
import Data.C.Ptr
import Derive.Prelude

import System.BSD.Kqueue.Flags
import System.Posix.File.FileDesc
import System.Posix.File.ReadRes

import public System.Posix.Poll.Struct
import public System.Posix.Poll.Types

%default total
%language ElabReflection

--------------------------------------------------------------------------------
-- FFI
--------------------------------------------------------------------------------

%foreign "C:kp_get_kevent_ident,kqueue-idris"
prim__get_kevent_ident : AnyPtr -> PrimIO Bits64

%foreign "C:kp_get_kevent_filter,kqueue-idris"
prim__get_kevent_filter : AnyPtr -> PrimIO Int16

%foreign "C:kp_get_kevent_flags,kqueue-idris"
prim__get_kevent_flags : AnyPtr -> PrimIO Bits16

%foreign "C:kp_get_kevent_fflags,kqueue-idris"
prim__get_kevent_fflags : AnyPtr -> PrimIO Bits32

%foreign "C:kp_get_kevent_data,kqueue-idris"
prim__get_kevent_data : AnyPtr -> PrimIO Int64

--------------------------------------------------------------------------------
-- Kqueue descriptor
--------------------------------------------------------------------------------

||| A file descriptor representing a kernel kqueue instance.
|||
||| The descriptor is returned by `kqueue(2)` and is subsequently used
||| when adding, deleting, and waiting for kqueue registrations.
export
record Kqueuefd where
  constructor KFD
  fd : Bits32

||| Return the underlying native file descriptor of a kqueue instance.
export %inline
kqueueFd : Kqueuefd -> Bits32
kqueueFd = fd

||| Convert a kqueue descriptor to the generic POSIX file descriptor type.
export %inline
Cast Kqueuefd Fd where
  cast = MkFd . fd

||| Convert the result of the native `kqueue(2)` call to a `Kqueuefd`.
export %inline
Cast CInt Kqueuefd where
  cast = KFD . cast

--------------------------------------------------------------------------------
-- kevent structure
--------------------------------------------------------------------------------

||| Linear wrapper around a pointer to a native `struct kevent`.
|||
||| Values of this type are normally obtained as elements of a
||| `CArray` filled by `kevent(2)`.
export
record SSKevent (s : Type) where
  constructor KE
  ptr : AnyPtr

export %inline
Struct SSKevent where
  swrap   = KE
  sunwrap = ptr

||| World-indexed native `struct kevent`.
public export
0 SKevent : Type
SKevent = SSKevent World

||| Native size of a `struct kevent`.
export %inline
SizeOf (SSKevent s) where
  sizeof_ = kevent_size

--------------------------------------------------------------------------------
-- Event accessors
--------------------------------------------------------------------------------

||| Read the `ident` field of a native `struct kevent`.
|||
||| For read and write filters, `ident` is the monitored file descriptor.
export %inline
keventIdent : SSKevent s -> F1 s Bits64
keventIdent (KE p) t =
  ffi (prim__get_kevent_ident p) t

||| Read the `filter` field of a native `struct kevent`.
export %inline
keventFilter : SSKevent s -> F1 s Int16
keventFilter (KE p) t =
  ffi (prim__get_kevent_filter p) t

||| Read the general `flags` field of a native `struct kevent`.
export %inline
keventFlags : SSKevent s -> F1 s Bits16
keventFlags (KE p) t =
  ffi (prim__get_kevent_flags p) t

||| Read the filter-specific `fflags` field of a native `struct kevent`.
export %inline
keventFflags : SSKevent s -> F1 s Bits32
keventFflags (KE p) t =
  ffi (prim__get_kevent_fflags p) t

||| Read the filter-specific `data` field of a native `struct kevent`.
export %inline
keventData : SSKevent s -> F1 s Int64
keventData (KE p) t =
  ffi (prim__get_kevent_data p) t

--------------------------------------------------------------------------------
-- PollEvent conversion
--------------------------------------------------------------------------------

||| Convert a kqueue filter into the corresponding POSIX polling event.
|||
||| `EVFILT_READ` maps to `POLLIN` and `EVFILT_WRITE` maps to `POLLOUT`.
||| Filters that do not represent file-descriptor readiness map to the
||| neutral polling event.
export
filterPollEvent : Int16 -> PollEvent
filterPollEvent flt =
  if flt == evfilt_read then
    POLLIN
  else if flt == evfilt_write then
    POLLOUT
  else
    neutral

||| Convert general kqueue event flags into their POSIX polling
||| equivalents.
|||
||| `EV_EOF` is represented as `POLLHUP`, while `EV_ERROR` is represented
||| as `POLLERR`. Both may be present simultaneously.
export
flagsPollEvent : Bits16 -> PollEvent
flagsPollEvent fl =
  let hup : PollEvent
      hup =
        if (fl .&. ev_eof) /= 0
          then POLLHUP
          else neutral

      err : PollEvent
      err =
        if (fl .&. ev_error) /= 0
          then POLLERR
          else neutral

   in hup <+> err

||| Convert a native kqueue event into a POSIX `PollPair`.
|||
||| Only `EVFILT_READ` and `EVFILT_WRITE` correspond to file-descriptor
||| readiness events consumed by the async poller. Signal, timer, user,
||| and other kqueue filters are therefore represented by `Nothing`.
|||
||| The returned polling mask combines the readiness event with any
||| corresponding EOF/hangup or error indication.
export
pollPair : SSKevent s -> F1 s (Maybe PollPair)
pollPair ev t =
  let ident # t := keventIdent ev t
      flt   # t := keventFilter ev t
      flgs  # t := keventFlags ev t
   in if flt == evfilt_read || flt == evfilt_write
        then
          let fd : Fd
              fd = MkFd (cast ident)

              evs : PollEvent
              evs = filterPollEvent flt <+> flagsPollEvent flgs

           in Just (PP fd evs) # t
        else
          Nothing # t

||| Conversion witness for decoding native `struct kevent` values into
||| optional POSIX `PollPair`s.
export %inline %hint
convKqueueEvent : Convert (Maybe PollPair)
convKqueueEvent =
  convStruct SSKevent pollPair
