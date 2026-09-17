module Main

import IO.Async.Loop.Kqueue

import Test.Async.BQueue
import Test.Async.Cancel
import Test.Async.Core
import Test.Async.Race
import Test.Async.Spec

main : IO ()
main =
  kqueueApp $ runTree $
    Node "Async Spec"
      [ Core.specs
      , Cancel.specs
      , Race.specs
      , BQueue.specs
      ]
