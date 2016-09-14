module Carpenter.Cedar
  ( cedarSpec
  , cedarSpec'
  , capture
  , capture'
  , watch
  , watch'
  , watchAndCapture
  , watchAndCapture'
  , ignore
  , ignore'
  , CedarProps
  , CedarHandler
  , CedarClass
  ) where

import Prelude
import React as React
import Carpenter (Yielder, Dispatcher, mkYielder, Render, Update, EventHandler)
import Control.Monad.Aff (launchAff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Unsafe (unsafeInterleaveEff)

-- | Type synonym for internal props of Cedar components.
type CedarProps state action =
  { initialState :: state
  , handler :: CedarHandler state action
  }

data CedarHandler state action
  = Capture (action -> EventHandler)
  | Watch (state -> EventHandler)
  | WatchAndCapture (action -> state -> EventHandler)
  | Ignore

-- | Type synonym for a ReactClass using the Cedar architecture with specific
-- | types for the component's state and actions.
type CedarClass state action = React.ReactClass (CedarProps state action)

-- | Creates a specification of a component using the Cedar architecture based
-- | on the supplied update and render functions.
-- |
-- | The Cedar architecture is highly based on the Elm architecture but it
-- | allows the existance of multiple sources of truth. That means it allow you
-- | to break the upward bubbling of actions up to the root component. You can
-- | choose to capture or ignore the actions dispatched by child components
-- | using the `capture` and `ignore` functions respectively.
cedarSpec
  :: ∀ state action eff
   . Update state (CedarProps state action) action eff
  -> Render state (CedarProps state action) action
  -> React.ReactSpec (CedarProps state action) state eff
cedarSpec update render = reactSpec { componentWillReceiveProps = componentWillReceiveProps }
  where
    reactSpec :: React.ReactSpec (CedarProps state action) state eff
    reactSpec = React.spec' getInitialState (getReactRender update render)

    getInitialState :: React.GetInitialState (CedarProps state action) state eff
    getInitialState this = React.getProps this >>= pure <<< _.initialState

    componentWillReceiveProps :: React.ComponentWillReceiveProps (CedarProps state action) state eff
    componentWillReceiveProps this props = void $ React.writeState this props.initialState

-- | Creates a specification of a Cedar component which emits a default initial
-- | action and has the specified update and render functions.
cedarSpec'
  :: ∀ state action eff
   . action
  -> Update state (CedarProps state action) action eff
  -> Render state (CedarProps state action) action
  -> React.ReactSpec (CedarProps state action) state eff
cedarSpec' action update render = reactSpec
  { componentWillReceiveProps = componentWillReceiveProps
  , componentDidMount = componentDidMount
  }
  where
    reactSpec :: React.ReactSpec (CedarProps state action) state eff
    reactSpec = React.spec' getInitialState (getReactRender update render)

    getInitialState :: React.GetInitialState (CedarProps state action) state eff
    getInitialState this = React.getProps this >>= pure <<< _.initialState

    componentWillReceiveProps :: React.ComponentWillReceiveProps (CedarProps state action) state eff
    componentWillReceiveProps this props = void $ React.writeState this props.initialState

    componentDidMount :: React.ComponentDidMount (CedarProps state action) state eff
    componentDidMount this = void $ do
      props <- React.getProps this
      state <- React.readState this
      let yield = mkYielder this
      let dispatch = mkDispatcher update props state yield
      unsafeInterleaveEff (launchAff (update yield dispatch action props state))

-- | Creates an element of the specificed React class with initial state
-- | and children, and captures its dispatched actions.
-- |
-- | `capture` and `capture'` are mostly used to dispatch actions to the parent
-- | component based on actions dispatched to the child component, e.g:
-- |
-- | ```purescript
-- | data MyParentAction
-- |   = ActionA
-- |   | ActionB String
-- |   | ChildAction MyChildAction
-- |
-- | -- ...
-- |
-- | render :: forall props. Render MyParentState props MyParentAction
-- | capture myChildClass (dispatch <<< ParentAction) 0 []
-- | ```
capture :: ∀ state action. React.ReactClass (CedarProps state action) -> (action -> EventHandler) -> state -> Array React.ReactElement -> React.ReactElement
capture reactClass handler state children = React.createElement reactClass {initialState: state, handler: Capture handler} children

-- | Creates an element of the specificed React class with initial state,
-- | and captures its dispatched actions.
capture' :: ∀ state action. React.ReactClass (CedarProps state action) -> (action -> EventHandler) -> state -> React.ReactElement
capture' reactClass handler state = React.createElement reactClass {initialState: state, handler: Capture handler} []

-- | Creates an element of the specified React class with initial state
-- | and children, and watches for changes to its internal state.
-- |
-- | `watch` and `watch'` are mostly used to dispatch actions to the parent
-- | component when the state of the child component changes, e.g:
watch :: ∀ state action. React.ReactClass (CedarProps state action) -> (state -> EventHandler) -> state -> Array React.ReactElement -> React.ReactElement
watch reactClass handler state children = React.createElement reactClass {initialState: state, handler: Watch handler} children

-- | Creates an element of the specified React class with initial state,
-- | and watches for changes to its internal state.
watch' :: ∀ state action. React.ReactClass (CedarProps state action) -> (state -> EventHandler) -> state -> React.ReactElement
watch' reactClass handler state = React.createElement reactClass {initialState: state, handler: Watch handler} []

-- | Creates an element of the specified React class with initial state
-- | and children, and watches for changes to its internal state.
-- | The handler function is then called with the dispatched action which
-- | caused the state change and the updated state.
watchAndCapture :: ∀ state action. React.ReactClass (CedarProps state action) -> (action -> state -> EventHandler) -> state -> Array React.ReactElement -> React.ReactElement
watchAndCapture reactClass handler state children = React.createElement reactClass {initialState: state, handler: WatchAndCapture handler} children

-- | Creates an element of the specified React class with initial state,
-- | and watches for changes to its internal state.
-- | The handler function is then called with the dispatched action which
-- | caused the state change and the updated state.
watchAndCapture' :: ∀ state action. React.ReactClass (CedarProps state action) -> (action -> state -> EventHandler) -> state -> React.ReactElement
watchAndCapture' reactClass handler state = React.createElement reactClass {initialState: state, handler: WatchAndCapture handler} []

-- | Creates an element of the specificed React class with initial state
-- | and children, and ignores its dispatched actions and internal state.
ignore :: ∀ state action. React.ReactClass (CedarProps state action) -> state -> Array React.ReactElement -> React.ReactElement
ignore reactClass state children = React.createElement reactClass {initialState: state, handler: Ignore} children

-- | Creates an element of the specificed React class with initial state,
-- | and ignores its dispatched actions and internal state.
ignore' :: ∀ state action. React.ReactClass (CedarProps state action) -> state -> React.ReactElement
ignore' reactClass state = React.createElement reactClass {initialState: state, handler: Ignore} []

--
--
getReactRender
  :: ∀ state action eff
   . Update state (CedarProps state action) action eff
  -> Render state (CedarProps state action) action
  -> React.Render (CedarProps state action) state eff
getReactRender update render this = do
  props <- React.getProps this
  state <- React.readState this
  children <- React.getChildren this
  let yield = mkYielder this
  let dispatch = mkDispatcher update props state yield
  pure $ render dispatch props state children

mkDispatcher :: ∀ state action eff. Update state (CedarProps state action) action eff -> (CedarProps state action) -> state -> Yielder state eff -> Dispatcher action
mkDispatcher update props state yield = dispatch
  where
    dispatch :: Dispatcher action
    dispatch action = void $ unsafeInterleaveEff $ launchAff do
      new <- update yield dispatch action props state
      liftEff $ case props.handler of
        Capture f -> f action
        Watch f -> f new
        WatchAndCapture f -> f action new
        _ -> pure unit
