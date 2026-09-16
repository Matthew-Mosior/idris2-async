module System.BSD.Kqueue.Flags

import Data.Bits
import Derive.Prelude

%default total
%language ElabReflection

--------------------------------------------------------------------------------
-- Filters
--------------------------------------------------------------------------------

||| Native `EVFILT_READ` filter value.
|||
||| This filter reports when data is available to read from a file
||| descriptor.
export %foreign "C:kp_evfilt_read,kqueue-idris"
evfilt_read : Int16

||| Native `EVFILT_WRITE` filter value.
|||
||| This filter reports when a file descriptor can accept data for writing.
export %foreign "C:kp_evfilt_write,kqueue-idris"
evfilt_write : Int16

||| Native `EVFILT_SIGNAL` filter value.
|||
||| This filter reports delivery of a registered signal.
export %foreign "C:kp_evfilt_signal,kqueue-idris"
evfilt_signal : Int16

||| Native `EVFILT_TIMER` filter value.
|||
||| This filter provides kernel-backed timer events.
export %foreign "C:kp_evfilt_timer,kqueue-idris"
evfilt_timer : Int16

||| Native `EVFILT_USER` filter value.
|||
||| This filter provides user-triggered kqueue events.
export %foreign "C:kp_evfilt_user,kqueue-idris"
evfilt_user : Int16

||| Supported kqueue event filters.
|||
||| Unlike epoll event masks, a kqueue registration is associated with
||| exactly one filter. Monitoring both reading and writing therefore
||| requires two registrations for the same file descriptor.
public export
data Filter
  = ReadFilter
  | WriteFilter
  | SignalFilter
  | TimerFilter
  | UserFilter

%runElab derive "Filter" [Show,Eq,Ord]

||| Convert a kqueue filter into its native `EVFILT_*` value.
public export
filterCode : Filter -> Int16
filterCode ReadFilter   = evfilt_read
filterCode WriteFilter  = evfilt_write
filterCode SignalFilter = evfilt_signal
filterCode TimerFilter  = evfilt_timer
filterCode UserFilter   = evfilt_user

||| Attempt to decode a native `EVFILT_*` value.
|||
||| Returns `Nothing` for filters not represented by `Filter`.
public export
filterFromCode : Int16 -> Maybe Filter
filterFromCode x =
  if x == evfilt_read then
    Just ReadFilter
  else if x == evfilt_write then
    Just WriteFilter
  else if x == evfilt_signal then
    Just SignalFilter
  else if x == evfilt_timer then
    Just TimerFilter
  else if x == evfilt_user then
    Just UserFilter
  else
    Nothing

--------------------------------------------------------------------------------
-- Flags
--------------------------------------------------------------------------------

||| Bitmask of native kqueue `EV_*` flags.
public export
record KqueueFlags where
  constructor F
  flags : Bits16

namespace KqueueFlags
  %runElab derive "KqueueFlags" [Show,Eq,Ord,FromInteger]

public export
Semigroup KqueueFlags where
  F x <+> F y = F (x .|. y)

public export
Monoid KqueueFlags where
  neutral = F 0

--------------------------------------------------------------------------------
-- Operations
--------------------------------------------------------------------------------

||| Registration operations used by the primitive kqueue API.
|||
||| `Add` installs a filter registration while `Del` removes it.
public export
data KqueueOp
  = Add
  | Del

%runElab derive "KqueueOp" [Show,Eq,Ord]

--------------------------------------------------------------------------------
-- Native flags
--------------------------------------------------------------------------------

||| Add or update a kqueue registration.
export %foreign "C:kp_ev_add,kqueue-idris"
ev_add : Bits16

||| Remove a kqueue registration.
export %foreign "C:kp_ev_delete,kqueue-idris"
ev_delete : Bits16

||| Enable a previously disabled registration.
export %foreign "C:kp_ev_enable,kqueue-idris"
ev_enable : Bits16

||| Disable a registration without removing it.
export %foreign "C:kp_ev_disable,kqueue-idris"
ev_disable : Bits16

||| Clear the event state after delivery.
export %foreign "C:kp_ev_clear,kqueue-idris"
ev_clear : Bits16

||| Automatically delete a registration after its first delivered event.
export %foreign "C:kp_ev_oneshot,kqueue-idris"
ev_oneshot : Bits16

||| Indicates an error associated with a returned kqueue event.
export %foreign "C:kp_ev_error,kqueue-idris"
ev_error : Bits16

||| Indicates EOF, disconnect, or hangup for applicable filters.
export %foreign "C:kp_ev_eof,kqueue-idris"
ev_eof : Bits16

--------------------------------------------------------------------------------
-- Operation encoding
--------------------------------------------------------------------------------

||| Convert a registration operation to its native kqueue flag.
public export
opCode : KqueueOp -> Bits16
opCode Add = ev_add
opCode Del = ev_delete

--------------------------------------------------------------------------------
-- Native structure information
--------------------------------------------------------------------------------

||| Size, in bytes, of a native `struct kevent` on the current platform.
|||
||| The value is obtained from the C support library using
||| `sizeof(struct kevent)`, avoiding assumptions about the structure's
||| platform-specific layout.
export %foreign "C:kp_kevent_size,kqueue-idris"
kevent_size : Bits32
