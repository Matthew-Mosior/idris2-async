||| A scheduler running on its own thread to schedule and
||| execute delayed computations.
module IO.Async.Internal.Timer

import Data.Maybe
import Data.SnocList
import Data.SortedMap
import IO.Async.Internal.Concurrent
import IO.Async.Internal.Loop
import IO.Async.Internal.Ref
import System.Clock

%default total

--------------------------------------------------------------------------------
-- Tasks
--------------------------------------------------------------------------------

||| A timed task to be executed by a `Timer`.
public export
record TimerTask where
  constructor TT
  due      : Clock Monotonic
  canceled : Ref Bool
  run      : PrimIO ()

0 TimerTasks : Type
TimerTasks = SortedMap (Clock Monotonic) (SnocList TimerTask)

addTask : TimerTask -> TimerTasks -> TimerTasks
addTask t = insertWith (<+>) t.due [<t]

nanosRemaining : (due,cur : Clock Monotonic) -> Integer
nanosRemaining due cur = toNano $ timeDifference due cur 

--------------------------------------------------------------------------------
-- Timer Run Loop
--------------------------------------------------------------------------------

export
record TimerST where
  constructor TST
  mutex : Mutex
  cond  : Condition
  alive : Ref Alive
  tasks : Ref TimerTasks

runTasks : List TimerTask -> PrimIO ()
runTasks []        w = MkIORes () w
runTasks (x :: xs) w =
  let MkIORes False w := readRef x.canceled w | MkIORes _ w => runTasks xs w
      MkIORes _     w := x.run w
   in runTasks xs w

getWork : TimerST -> PrimIO Work
getWork (TST mu co al ts) =
  withMutex mu $ \w =>
    let MkIORes Run w := readRef al w | MkIORes _ w => done w
        MkIORes m   w := readRef ts w
     in case leftMost m of
          Nothing     => waitNoWork co mu w
          Just (k,sv) =>
            let MkIORes c w := toPrim (clockTime Monotonic) w
                diff        := nanosRemaining k c
             in case diff <= 0 of
                  False => sleepNoWork co mu (diff `div` 1000) w
                  True  =>
                    let MkIORes _ w := writeRef ts (delete k m) w
                     in work (runTasks $ sv <>> []) w

covering
runLoop : TimerST -> PrimIO ()
runLoop ts w =
  let MkIORes (W p) w := getWork ts w | MkIORes Done w => MkIORes () w
      MkIORes _     w := p w
   in runLoop ts w

--------------------------------------------------------------------------------
-- Timer
--------------------------------------------------------------------------------

public export
record Timer where
  constructor T
  st : TimerST
  id : ThreadID

||| Submits a task to the timer.
|||
||| The timer will process it once it becomes due. The task can be
||| canceled externally by setting its `canceled` flag to `True`.
export
submit : Timer -> TimerTask -> PrimIO ()
submit t tt =
  withMutex t.st.mutex $ \w =>
    let MkIORes _ w := modRef t.st.tasks (addTask tt) w
     in conditionSignal t.st.cond w

||| Stops the `Timer` by setting its `Alive` flag to `Stop`.
|||
||| The thread the timer is currently running on will wake up
||| and stop processing more timed tasks. This will block the
||| caller until the timer's thread terminates.
export
stop : Timer -> IO ()
stop t = do
  primIO $ withMutex t.st.mutex $ \w =>
    let MkIORes _ w := writeRef t.st.alive Stop w
     in conditionSignal t.st.cond w
  threadWait t.id

||| Creates an asynchronous scheduler for timed tasks.
|||
||| This sets up a new event loop for processing timed tasks
||| on a single additional thread. The thread will usually wait until
||| either the next scheduled task is due or a new task is submitted
||| via `submit`.
export covering
mkTimer : IO Timer
mkTimer = do
  m  <- primIO mkMutex
  c  <- primIO makeCondition
  s  <- primIO (newRef Run)
  q  <- primIO (newRef empty)
  let tst := TST m c s q
  id <- fork $ fromPrim $ runLoop tst
  pure (T tst id)
