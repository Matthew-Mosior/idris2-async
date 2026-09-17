module IO.Async.Loop.Kqueue

import public Data.Nat
import Control.Monad.Elin
import Data.Array.Core as AC
import Data.Array.Mutable
import Data.Bits
import Data.DPair
import Data.Linear.Traverse1
import Data.Queue
import Data.Vect

import IO.Async.Internal.Ref
import IO.Async.Loop.Poller
import IO.Async.Loop.Queue
import IO.Async.Loop.SignalST
import IO.Async.Loop.TimerST
import IO.Async.Signal

import public IO.Async
import public IO.Async.Loop
import public IO.Async.Loop.PollH
import public IO.Async.Loop.Posix
import public IO.Async.Loop.SignalH
import public IO.Async.Loop.TimerH

import System
import System.Clock
import System.BSD.Kqueue.Prim
import System.Posix.File.Prim
import System.Posix.Limits

%default total

--------------------------------------------------------------------------------
-- Kqueue
--------------------------------------------------------------------------------

||| State used for file-descriptor polling with `kqueue`.
record Kqueue where
  constructor P
  ||| Number of file descriptors currently waiting to be polled.
  waiting : IORef Nat
  ||| Maximum number of files that can be opened.
  |||
  ||| This is initialized from `SC_OPEN_MAX` and is also used as the size
  ||| of the file-handle table and event buffer.
  maxFiles : Nat
  ||| File event handles indexed by file descriptor.
  |||
  ||| A registered descriptor has a callback installed at its descriptor
  ||| index. Unregistered descriptors contain `hdummy`.
  handles : IOArray maxFiles FileHandle
  ||| Native event buffer populated by `kevent(2)`.
  events : CArrayIO maxFiles SKevent
  ||| The kqueue descriptor used for registration and polling.
  kqueue : Kqueuefd

||| Initialize the internal state of a kqueue poller.
mkKqueue : IO1 Kqueue
mkKqueue t =
  let maxfiles    := cast {to = Nat} (sysconf SC_OPEN_MAX)
      waiting # t := ref1 Z t
      handles # t := marray1 maxfiles hdummy t
      events  # t := malloc1 SKevent maxfiles t
      kqueue  # t := dieOnErr kqueueCreate t
   in P waiting maxfiles handles events kqueue # t

--------------------------------------------------------------------------------
-- Registrations
--------------------------------------------------------------------------------

||| The kqueue filters installed for one asynchronous file operation.
|||
||| Unlike epoll, kqueue associates one filter with each registration.
||| Waiting for both reading and writing therefore requires two kernel
||| registrations for the same file descriptor.
record Registration where
  constructor R
  read  : Bool
  write : Bool

||| Convert a POSIX polling event mask into a kqueue registration.
|||
||| Only readable and writable readiness are relevant to the asynchronous
||| file poller. Error and hangup events are reported by the kernel rather
||| than explicitly registered.
%inline
registration : PollEvent -> Registration
registration ev =
  R
    (hasEvent ev POLLIN)
    (hasEvent ev POLLOUT)

||| Whether a registration contains at least one kqueue filter.
%inline
registered : Registration -> Bool
registered (R r w) = r || w

--------------------------------------------------------------------------------
-- Polling for File Events
--------------------------------------------------------------------------------

parameters (p : Kqueue)

  ||| Look up the callback associated with a file descriptor.
  |||
  ||| File descriptors outside the configured descriptor range resolve to
  ||| the dummy callback.
  %inline
  getHandle : Fd -> IO1 FileHandle
  getHandle f t =
    case tryNatToFin (cast f.fd) of
      Just v  => AC.get p.handles v t
      Nothing => hdummy # t

  ||| Invoke all callbacks corresponding to events returned by kqueue.
  |||
  ||| If two events for the same descriptor occur in a single kernel batch
  ||| (for example read and write readiness), the first invocation performs
  ||| cleanup and replaces the handle with `hdummy`. The second event is
  ||| therefore safely ignored.
  handleEvs : List PollPair -> IO1 ()
  handleEvs []             t = () # t
  handleEvs (PP fd ev :: es) t =
    let h # t := getHandle fd t
        _ # t := h ev t
     in handleEvs es t

  ||| Wait for kqueue file events for at most the supplied duration.
  pollWaitImpl : (timeout : Clock Duration) -> IO1 ()
  pollWaitImpl to t =
    let vs # t := dieOnErr (kqueueWaitVals p.kqueue p.events to) t
     in handleEvs vs t

  ||| Perform a non-blocking kqueue poll when descriptors are registered.
  |||
  ||| As in the epoll implementation, the kernel call is skipped entirely
  ||| when no descriptors are currently waiting.
  pollImpl : IO1 ()
  pollImpl t =
    let S _ # t := read1 p.waiting t
        | _ # t => () # t
     in pollWaitImpl (makeDuration 0 0) t

  ||| Release the resources owned by the kqueue poller.
  release : IO1 ()
  release t =
    let _ # t := free1 p.events t
     in toF1 (close' (the Fd $ cast p.kqueue)) t

--------------------------------------------------------------------------------
-- File Polling
--------------------------------------------------------------------------------

parameters (p         : Kqueue)
           (fd        : Fd)
           (ev        : PollEvent)
           (autoClose : Bool)
           (cb        : Either Errno PollEvent -> IO1 ())

  ||| Submit one kqueue registration operation for the current descriptor.
  %inline
  ctl : KqueueOp -> Filter -> E1 World [Errno] ()
  ctl op flt =
    kqueueCtl p.kqueue op fd flt

  ||| Close the monitored file descriptor when automatic closing is enabled.
  |||
  ||| This must be invoked only after the user callback has run.
  %inline
  closefd : IO1 ()
  closefd =
    when1 autoClose (toF1 $ close' fd)

  ||| Remove all filters belonging to a registration.
  |||
  ||| Deletions are attempted independently so that failure while deleting
  ||| one filter does not prevent cleanup of the other.
  unregister : Registration -> IO1 ()
  unregister (R False False) t =
    () # t
  unregister (R True False) t =
    e1ToF1 (ctl Del ReadFilter) t
  unregister (R False True) t =
    e1ToF1 (ctl Del WriteFilter) t
  unregister (R True True) t =
    let _ # t := e1ToF1 (ctl Del ReadFilter) t
     in e1ToF1 (ctl Del WriteFilter) t

  ||| Register all filters required by an asynchronous poll request.
  |||
  ||| When both read and write filters are requested, read registration is
  ||| installed first. If installing the write filter fails, the previously
  ||| installed read filter is removed before propagating the original
  ||| registration error.
  register : Registration -> E1 World [Errno] ()
  register (R False False) t =
    E (Here EINVAL) t
  register (R True False) t =
    ctl Add ReadFilter t
  register (R False True) t =
    ctl Add WriteFilter t
  register (R True True) t =
    case ctl Add ReadFilter t of
      E err t =>
        E err t
      R _ t =>
        case ctl Add WriteFilter t of
          R _ t =>
            R () t
          E err t =>
            -- Registration is transactional from the async poller's
            -- perspective. Roll back the read filter before returning
            -- the write-registration failure.
            case ctl Del ReadFilter t of
              R _ t =>
                E err t
              E _ t =>
                -- Preserve the original registration error.
                E err t

  ||| Reset the callback slot and remove all installed kqueue filters.
  |||
  ||| The waiting counter is decremented before the descriptor is
  ||| unregistered, mirroring the lifecycle used by the epoll poller.
  %inline
  cleanup : Registration -> Fin p.maxFiles -> IO1 ()
  cleanup reg v t =
    let _ # t := Queue.dec p.waiting t
        _ # t := AC.set p.handles v hdummy t
     in unregister reg t

  ||| Handle a ready descriptor.
  |||
  ||| Cleanup is performed before invoking the user callback. The descriptor
  ||| is closed afterward when `autoClose` is enabled.
  %inline
  act : Registration -> Fin p.maxFiles -> FileHandle
  act reg v event t =
    let _ # t := Kqueue.cleanup reg v t
        _ # t := cb (Right event) t
     in closefd t

  ||| Complete a polling request before a kernel registration has become
  ||| active.
  |||
  ||| The callback is invoked immediately, the file descriptor is closed
  ||| when requested, and a no-op cancellation hook is returned.
  %inline
  abrt : Either Errno PollEvent -> IO1 (IO1 ())
  abrt res t =
    let _ # t := cb res t
        _ # t := closefd t
     in unit1 # t

  ||| Cancel an active file polling request.
  |||
  ||| Cancellation removes the installed filters and optionally closes the
  ||| monitored descriptor without invoking the user callback.
  %inline
  cncl : Registration -> Fin p.maxFiles -> FileHandle
  cncl reg v _ t =
    let _ # t := Kqueue.cleanup reg v t
     in closefd t

  ||| Register a file descriptor with the kqueue poller.
  |||
  ||| The returned `IO1 ()` action is the cancellation hook for the
  ||| registration.
  |||
  ||| A shared atomic flag protects the race between kernel event delivery
  ||| and external cancellation. Exactly one path is therefore allowed to
  ||| perform cleanup.
  pollKqueueFile : IO1 (IO1 ())
  pollKqueueFile t =
    case tryNatToFin (cast fd.fd) of
      Nothing =>
        abrt (Left EINVAL) t
      Just v =>
        let reg := registration ev
         in case register reg t of
              -- Registration failed before the callback became active.
              E (Here err) t =>
                abrt (Left err) t
              -- Registration succeeded. Install the callback and expose
              -- the cancellation hook.
              R _ t =>
                let r # t :=
                      ref1 True t
                    _ # t :=
                      AC.set
                        p.handles
                        v
                        (\event => once r (act reg v event))
                        t
                    _ # t :=
                      Queue.inc p.waiting t
                 in once r (Kqueue.cleanup reg v) # t

--------------------------------------------------------------------------------
-- Poller
--------------------------------------------------------------------------------

||| Initialize a BSD/macOS kqueue-backed asynchronous poller.
export
kqueuePoller : IO1 Poller
kqueuePoller t =
  let kq # t := mkKqueue t
   in MkPoller
        (pollImpl kq)
        (pollWaitImpl kq)
        (release kq)
        (pollKqueueFile kq)
        # t

--------------------------------------------------------------------------------
-- Application Runner
--------------------------------------------------------------------------------

||| Simplified version of `app` using the kqueue poller.
|||
||| The number of worker threads is read from the
||| `IDRIS2_ASYNC_THREADS` environment variable, with the same default used
||| by the other async event-loop implementations.
|||
||| The running program is cancelled when `SIGINT` is received.
|||
||| By default only `SIGINT` is masked. To handle additional signals within
||| the program, pass them using `{sigs = [...]}`. The `Has SIGINT sigs`
||| constraint ensures that `SIGINT` remains present.
export covering
kqueueApp
  : {default [SIGINT] sigs : List Signal}
  -> Has SIGINT sigs
  => Async Poll [] ()
  -> IO ()
kqueueApp {sigs} prog = do
  n <- asyncThreads
  app n sigs kqueuePoller cprog
  where
    cprog : Async Poll [] ()
    cprog =
      race_
        [ prog
        , dropErrs {es = [Errno]} $ onSignal SIGINT (pure ())
        ]
