module Lunapark.API where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Eff.Ref as Ref
import Control.Monad.Error.Class (class MonadThrow, class MonadError, throwError)
import Control.Monad.Reader.Class (class MonadAsk, ask)
import Control.Monad.State.Class (class MonadState)
import Control.Monad.Rec.Class (class MonadRec)
import Control.Monad.Free (Free, foldFree)
import Data.Time.Duration (Milliseconds(..))
import Data.Argonaut as J
import Data.Bifunctor (lmap)
import Data.Either (Either(..), either)
import Data.List (List(..), (:))
import Data.Maybe (Maybe(..))
import Data.Map as Map
import Data.Newtype (class Newtype, un, wrap)
import Data.Traversable as T
import Data.Symbol (SProxy(..))
import Data.StrMap as SM
import Lunapark.Affjax as LA
import Lunapark.Error as LE
import Lunapark.Types as LT
import Lunapark.Endpoint as LP
import Node.Buffer as B
import Node.FS.Aff as FS
import Network.HTTP.Affjax (AJAX)
import Unsafe.Coerce (unsafeCoerce)
import Run as R
import Run.Except (EXCEPT, runExcept, throw)
import Run.Except as RE
import Debug.Trace as DT
import Unsafe.Coerce (unsafeCoerce)

type LunaparkEffects e =
  ( ajax ∷ AJAX
  , ref ∷ Ref.REF
  , buffer ∷ B.BUFFER
  , fs ∷ FS.FS
  | e)

-- | Example
-- | ```purescript
-- | runLunapark ← init "http://localhost:4444/wd/hub" SM.empty
-- | result ← runLunapark do
-- |   setTimeouts timeouts
-- |   go "http://google.com"
-- |   findElement ...
-- | ```
init
  ∷ ∀ e m a
  . MonadAff (LunaparkEffects e) m
  ⇒ MonadRec m
  ⇒ String
  → LT.CapabilitiesRequest
  → m (Lunapark e a → m (Either LE.Error a))
init uri caps = do
  sessObj ← liftAff $ LP.post uri (LP.Session : Nil) $ LT.encodeCapabilitiesRequest caps
  case lmap LE.unknownError <<< LT.decodeCreateSessionResponse =<< sessObj of
    Left e → pure \_ → pure $ Left e
    Right a → pure \actions → liftAff $ interpret uri a actions

interpret ∷ ∀ a e. String → LT.CreateSessionResponse → Lunapark e a → Aff (LunaparkEffects e) (Either LE.Error a)
interpret uri {session, capabilities} actions = do
  id
  --expandEffectRows
    $ R.runBaseAff'
    $ runExcept
    $ runLunapark uri session capabilities
    $ un Lunapark actions
--  where
  -- This is definitely safe, because more effects is not less effects
--  expandEffectRows ∷ ∀ m r0 r1 r. Union r0 r1 r ⇒ m r0 ~> m r
--  expandEffectRows = unsafeCoerce

data LunaparkF a
  = Quit a
  | Status (LT.ServerStatus → a)
  | GetTimeouts (LT.Timeouts → a)
  | SetTimeouts LT.Timeouts a
  | GoTo String a
  | GetUrl (String → a)
  | Forward a
  | Back a
  | Refresh a
  | GetTitle (String → a)
  | GetWindowHandle (LT.WindowHandle → a)
  | GetWindowHandles (Array LT.WindowHandle → a)
  | CloseWindow a
  | SwitchToWindow LT.WindowHandle a
  | SwitchToFrame LT.FrameId a
  | SwitchToParentFrame a
  | GetWindowRectangle (LT.Rectangle → a)
  | SetWindowRectangle LT.Rectangle a
  | MaximizeWindow a
  | MinimizeWindow a
  | FullscreenWindow a
  | ExecuteScript LT.Script (J.Json → a)
  | ExecuteScriptAsync LT.Script (J.Json → a)
  | GetAllCookies (Array LT.Cookie → a)
  | GetCookie String (LT.Cookie → a)
  | DeleteCookie String a
  | DeleteAllCookies a
  | AddCookie LT.Cookie a
  | DismissAlert a
  | AcceptAlert a
  | GetAlertText (String → a)
  | SendAlertText String a
  | Screenshot String a
  | ElementScreenshot LT.Element String a
  | FindElement LT.Locator (LT.Element → a)
  | FindElements LT.Locator (Array LT.Element → a)
  | FindElementInElement LT.Element LT.Locator (LT.Element → a)
  | FindElementsInElement LT.Element LT.Locator (Array LT.Element → a)

derive instance functorLunaparkF ∷ Functor LunaparkF

type BaseRun r e = R.Run
  ( except ∷ EXCEPT LE.Error
  , aff ∷ R.AFF (LunaparkEffects e)
  , eff ∷ R.EFF (LunaparkEffects e)
  | r)

type RunLunapark e = BaseRun (lunapark ∷ LUNAPARK) e

newtype Lunapark e a = Lunapark (RunLunapark e a)

_lunapark = SProxy ∷ SProxy "lunapark"
type LUNAPARK = R.FProxy LunaparkF

liftLunapark ∷ ∀ a e. LunaparkF a → Lunapark e a
liftLunapark = Lunapark <<< R.lift _lunapark

derive instance newtypeLunapark ∷ Newtype (Lunapark e a) _
derive newtype instance functorLunapark ∷ Functor (Lunapark e)
derive newtype instance applyLunapark ∷ Apply (Lunapark e)
derive newtype instance applicativeLunapark ∷ Applicative (Lunapark e)
derive newtype instance bindLunapark ∷ Bind (Lunapark e)
derive newtype instance monadLunapark ∷ Monad (Lunapark e)

quit ∷ ∀ e. Lunapark e Unit
quit = liftLunapark $ Quit unit

status ∷ ∀ e. Lunapark e LT.ServerStatus
status = liftLunapark $ Status id

setTimeouts ∷ ∀ e. LT.Timeouts → Lunapark e Unit
setTimeouts ts = liftLunapark $ SetTimeouts ts unit

getTimeouts ∷ ∀ e. Lunapark e LT.Timeouts
getTimeouts = liftLunapark $ GetTimeouts id

go ∷ ∀ e. String → Lunapark e Unit
go uri = liftLunapark $ GoTo uri unit

getUrl ∷ ∀ e. Lunapark e String
getUrl = liftLunapark $ GetUrl id

forward ∷ ∀ e. Lunapark e Unit
forward = liftLunapark $ Forward unit

back ∷ ∀ e. Lunapark e Unit
back = liftLunapark $ Back unit

refresh ∷ ∀ e. Lunapark e Unit
refresh = liftLunapark $ Refresh unit

getTitle ∷ ∀ e. Lunapark e String
getTitle = liftLunapark $ GetTitle id

getWindowHandle ∷ ∀ e. Lunapark e LT.WindowHandle
getWindowHandle = liftLunapark $ GetWindowHandle id

getWindowHandles ∷ ∀ e. Lunapark e (Array LT.WindowHandle)
getWindowHandles = liftLunapark $ GetWindowHandles id

closeWindow ∷ ∀ e. Lunapark e Unit
closeWindow = liftLunapark $ CloseWindow unit

switchToWindow ∷ ∀ e. LT.WindowHandle → Lunapark e Unit
switchToWindow w = liftLunapark $ SwitchToWindow w unit

switchToFrame ∷ ∀ e. LT.FrameId → Lunapark e Unit
switchToFrame f = liftLunapark $ SwitchToFrame f unit

switchToParentFrame ∷ ∀ e. Lunapark e Unit
switchToParentFrame = liftLunapark $ SwitchToParentFrame unit

getWindowRectangle ∷ ∀ e. Lunapark e LT.Rectangle
getWindowRectangle = liftLunapark $ GetWindowRectangle id

setWindowRectangle ∷ ∀ e. LT.Rectangle → Lunapark e Unit
setWindowRectangle r = liftLunapark $ SetWindowRectangle r unit

maximizeWindow ∷ ∀ e. Lunapark e Unit
maximizeWindow = liftLunapark $ MaximizeWindow unit

minimizeWindow ∷ ∀ e. Lunapark e Unit
minimizeWindow = liftLunapark $ MinimizeWindow unit

fullscreenWindow ∷ ∀ e. Lunapark e Unit
fullscreenWindow = liftLunapark $ FullscreenWindow unit

executeScript ∷ ∀ e. LT.Script → Lunapark e J.Json
executeScript script = liftLunapark $ ExecuteScript script id

executeScriptAsync ∷ ∀ e. LT.Script → Lunapark e J.Json
executeScriptAsync script = liftLunapark $ ExecuteScriptAsync script id

getAllCookies ∷ ∀ e. Lunapark e (Array LT.Cookie)
getAllCookies = liftLunapark $ GetAllCookies id

getCookie ∷ ∀ e. String → Lunapark e LT.Cookie
getCookie name = liftLunapark $ GetCookie name id

addCookie ∷ ∀ e. LT.Cookie → Lunapark e Unit
addCookie cookie = liftLunapark $ AddCookie cookie unit

deleteCookie ∷ ∀ e. String → Lunapark e Unit
deleteCookie name = liftLunapark $ DeleteCookie name unit

deleteAllCookies ∷ ∀ e. Lunapark e Unit
deleteAllCookies = liftLunapark $ DeleteAllCookies unit

dismissAlert ∷ ∀ e. Lunapark e Unit
dismissAlert = liftLunapark $ DismissAlert unit

acceptAlert ∷ ∀ e. Lunapark e Unit
acceptAlert = liftLunapark $ AcceptAlert unit

getAlertText ∷ ∀ e. Lunapark e String
getAlertText = liftLunapark $ GetAlertText id

sendAlertText ∷ ∀ e. String → Lunapark e Unit
sendAlertText txt = liftLunapark $ SendAlertText txt unit

screenshot ∷ ∀ e. String → Lunapark e Unit
screenshot fp = liftLunapark $ Screenshot fp unit

elementScreenshot ∷ ∀ e. LT.Element → String → Lunapark e Unit
elementScreenshot el fp = liftLunapark $ ElementScreenshot el fp unit

findElement ∷ ∀ e. LT.Locator → Lunapark e LT.Element
findElement l = liftLunapark $ FindElement l id

findElements ∷ ∀ e. LT.Locator → Lunapark e (Array LT.Element)
findElements l = liftLunapark $ FindElements l id

findElementInElement ∷ ∀ e. LT.Element → LT.Locator → Lunapark e LT.Element
findElementInElement el l = liftLunapark $ FindElementInElement el l id

findElementsInElement ∷ ∀ e. LT.Element → LT.Locator → Lunapark e (Array LT.Element)
findElementsInElement el l = liftLunapark $ FindElementsInElement el l id

runLunapark ∷ ∀ e. String → LT.SessionId → Array LT.Capability → RunLunapark e ~> BaseRun () e
runLunapark uri session capabilities a = do
  timeoutsRef ←
    R.liftEff $ Ref.newRef
      { implicit: Milliseconds 0.0
      , pageLoad: Milliseconds 300000.0
      , script: Milliseconds 30000.0
      }
  requestMapRef ← R.liftEff $ Ref.newRef Map.empty
  let input =
        { timeoutsRef
        , requestMapRef
        , uri
        , session
        , capabilities
        }
  R.interpretRec (R.on _lunapark (handleLunapark input) R.send) a

type HandleLunaparkInput =
  { session ∷ LT.SessionId
  , timeoutsRef ∷ Ref.Ref LT.Timeouts
  , requestMapRef ∷ Ref.Ref (Map.Map String Boolean)
  , uri ∷ String
  , capabilities ∷ Array LT.Capability
  }

handleLunapark ∷ ∀ e. HandleLunaparkInput → LunaparkF ~> BaseRun () e
handleLunapark inp = case _ of
  Quit next → do
    _ ← delete $ inSession : Nil
    pure next
  Status cont → do
    res ← get $ LP.Status : Nil
    ss ← throwLeft $ LT.decodeServerStatus res
    pure $ cont ss
  GetTimeouts cont → do
    res ← R.liftEff $ Ref.readRef inp.timeoutsRef
    pure $ cont res
  SetTimeouts ts next → do
    R.liftEff $ Ref.writeRef inp.timeoutsRef ts
    withFallback "set timeouts"
      { w3c: void $ post (inSession : LP.Timeouts : Nil) (LT.encodeTimeouts ts)
      , jsonWire: do
           T.for_ (LT.encodeLegacyTimeouts ts) \j →
             void $ post (inSession : LP.Timeouts : Nil) j
      }
    pure next
  GoTo uri next → do
    _ ← post (inSession : LP.Url : Nil) $ LT.encodeGoRequest uri
    pure next
  GetUrl cont → do
    res ← get $ inSession : LP.Url : Nil
    map cont $ throwLeft $ J.decodeJson res
  Back next → do
    _ ← post_ (inSession : LP.Back : Nil)
    pure next
  Forward next → do
    _ ← post_ (inSession : LP.Forward : Nil)
    pure next
  Refresh next → do
    _ ← post_ (inSession : LP.Refresh : Nil)
    pure next
  GetTitle cont → do
    res ← get (inSession : LP.Title : Nil)
    map cont $ throwLeft $ J.decodeJson res
  GetWindowHandle cont → do
    res ← withFallback "get window handle"
      { w3c: get (inSession : LP.Window : Nil)
      , jsonWire: get (inSession : LP.WindowHandle : Nil)
      }
    map cont $ throwLeft $ LT.decodeWindowHandle res
  GetWindowHandles cont → do
    res ← withFallback "get window handles"
      { w3c: get (inSession : LP.Window : LP.Handles : Nil)
      , jsonWire: get (inSession : LP.WindowHandles : Nil)
      }
    map cont $ throwLeft $ T.traverse LT.decodeWindowHandle =<< J.decodeJson res
  CloseWindow next → do
    _ ← delete (inSession : LP.Window : Nil)
    pure next
  SwitchToWindow w next → do
    _ ← post (inSession : LP.Window : Nil) (LT.encodeSwitchToWindowRequest w)
    pure next
  SwitchToFrame fid next → do
    _ ← post (inSession : LP.Frame : Nil) (LT.encodeFrameId fid)
    pure next
  SwitchToParentFrame next → do
    _ ← post_ (inSession : LP.Frame : LP.Parent : Nil)
    pure next
  GetWindowRectangle cont → do
    res ← withFallback "get window rectangle"
      { w3c: do
           res ← get (inSession : LP.Window : LP.Rect : Nil)
           throwLeft $ LT.decodeRectangle res
      , jsonWire: do
           position ← get (inSession : LP.Window : LP.Position : Nil)
           size ← get (inSession : LP.Window : LP.Size : Nil)
           throwLeft $ LT.decodeRectangleLegacy { position, size }
      }
    pure $ cont res
  SetWindowRectangle r next → do
    withFallback "set window rectangle"
      { w3c: do
           void $ post (inSession : LP.Window : LP.Rect : Nil) (LT.encodeRectangle r)
      , jsonWire: do
           let js = LT.encodeRectangleLegacy r
           _ ← post (inSession : LP.Window : LP.Size : Nil) js.size
           void $ post (inSession : LP.Window : LP.Position : Nil) js.position
      }
    pure next
  MaximizeWindow next → do
    _ ← post_ (inSession : LP.Window : LP.Maximize : Nil)
    pure next
  MinimizeWindow next → do
    _ ← post_ (inSession : LP.Window : LP.Minimize : Nil)
    pure next
  FullscreenWindow next → do
    _ ← post_ (inSession : LP.Window : LP.Fullscreen : Nil)
    pure next
  ExecuteScript script cont → do
    map cont $ withFallback "execute script"
      { w3c: post (inSession : LP.Execute : LP.Sync : Nil) (LT.encodeScript script)
      , jsonWire: post (inSession : LP.Execute : Nil) (LT.encodeScript script)
      }
  ExecuteScriptAsync script cont → do
    map cont $ withFallback "execute script async"
      { w3c: post (inSession : LP.Execute : LP.Async : Nil) (LT.encodeScript script)
      , jsonWire: post (inSession : LP.ExecuteAsync : Nil) (LT.encodeScript script)
      }
  GetAllCookies cont → do
    res ← get (inSession : LP.Cookies : Nil)
    map cont $ throwLeft $ T.traverse LT.decodeCookie =<< J.decodeJson res
  GetCookie name cont → do
    res ← get (inSession : LP.Cookie name : Nil)
    map cont $ throwLeft $ LT.decodeCookie res
  DeleteAllCookies next → do
    _ ← delete (inSession : LP.Cookies : Nil)
    pure next
  DeleteCookie name next → do
    _ ← delete (inSession : LP.Cookie name : Nil)
    pure next
  AddCookie cookie next → do
    _ ← post (inSession : LP.Cookies : Nil) (LT.encodeCookie cookie)
    pure next
  DismissAlert next → do
    _ ← withFallback "dismiss alert"
      { w3c: post_ (inSession : LP.Alert : LP.Dismiss : Nil)
      , jsonWire: post_ (inSession : LP.DismissAlert : Nil)
      }
    pure next
  AcceptAlert next → do
    _ ← withFallback "accept alert"
      { w3c: post_ (inSession : LP.Alert : LP.Accept : Nil)
      , jsonWire: post_ (inSession : LP.AcceptAlert : Nil)
      }
    pure next
  GetAlertText cont → do
    res ← withFallback "get alert text"
      { w3c: get (inSession : LP.Alert : LP.Text : Nil)
      , jsonWire: get (inSession : LP.AlertText : Nil)
      }
    map cont $ throwLeft $ J.decodeJson res
  SendAlertText str next → do
    _ ← withFallback "send alert text"
      { w3c: post (inSession : LP.Alert : LP.Text : Nil) (LT.encodeSendKeysRequest str)
      , jsonWire: post (inSession : LP.AlertText : Nil) (LT.encodeSendKeysRequest str)
      }
    pure next
  Screenshot fp next → do
    res ← get (inSession : LP.Screenshot : Nil)
    screenshotPack ← throwLeft $ LT.decodeScreenshot res
    buffer ← R.liftEff $ B.fromString screenshotPack.content screenshotPack.encoding
    R.liftAff $ FS.writeFile fp buffer
    pure next
  ElementScreenshot el fp next → do
    res ← get (inSession : LP.InElement el : LP.Screenshot : Nil)
    screenshotPack ← throwLeft $ LT.decodeScreenshot res
    buffer ← R.liftEff $ B.fromString screenshotPack.content screenshotPack.encoding
    R.liftAff $ FS.writeFile fp buffer
    pure next
  FindElement loc cont → do
    res ← post (inSession : LP.Element : Nil) (LT.encodeLocator loc)
    map cont $ throwLeft $ LT.decodeElement res
  FindElements loc cont → do
    res ← post (inSession : LP.Elements : Nil) (LT.encodeLocator loc)
    map cont $ throwLeft $ T.traverse LT.decodeElement =<< J.decodeJson res
  FindElementInElement el loc cont → do
    res ← post (inSession : LP.InElement el : LP.Element : Nil) (LT.encodeLocator loc)
    map cont $ throwLeft $ LT.decodeElement res
  FindElementsInElement el loc cont → do
    res ← post (inSession : LP.InElement el : LP.Elements : Nil) (LT.encodeLocator loc)
    map cont $ throwLeft $ T.traverse LT.decodeElement =<< J.decodeJson res

  where
  delete a = liftAndRethrow $ LP.delete inp.uri a
  post a b = liftAndRethrow $ LP.post inp.uri a b
  get a = liftAndRethrow $ LP.get inp.uri a
  post_ a = liftAndRethrow $ LP.post_ inp.uri a

  withFallback ∷ ∀ a. String → { w3c ∷ BaseRun () e a, jsonWire ∷ BaseRun () e a } → BaseRun () e a
  withFallback key { w3c: try, jsonWire: fallback } = do
    mp ← R.liftEff $ Ref.readRef inp.requestMapRef
    case DT.spy $ Map.lookup key mp of
      Just true → try
      Just false → fallback
      Nothing →
        let
          try' = do
            a ← try
            R.liftEff $ Ref.modifyRef inp.requestMapRef (Map.insert key true)
            pure a
          fallback' = do
            a ← fallback
            R.liftEff $ Ref.modifyRef inp.requestMapRef (Map.insert key false)
            pure a
        in catch try' \_ → fallback'

  inSession ∷ LP.EndpointPart
  inSession = LP.InSession inp.session

  liftAndRethrow ∷ ∀ e ω. Aff (LunaparkEffects e) (Either LE.Error ω) → BaseRun () e ω
  liftAndRethrow a = do
    res ← R.liftAff a
    RE.rethrow res

  throwLeft ∷ ∀ ω. Either String ω → BaseRun () e ω
  throwLeft = RE.rethrow <<< lmap LE.unknownError

-- Safe, since we actually want handler and result have same rows not, remove except
catch ∷ ∀ e r a. R.Run (except ∷ EXCEPT e|r) a → (e → R.Run (except ∷ EXCEPT e|r) a) → R.Run (except ∷ EXCEPT e|r) a
catch = unsafeCoerce $ flip RE.catch


--interpret ∷ ∀ e. LunaparkF ~> Aff (ajax ∷ AJAX|e)
--interpret = unsafeCoerce


{-
import Prelude







import Debug.Trace as DT

type Config =
  { session ∷ LT.SessionId
  , baseURI ∷ String
  , capabilities ∷ Array LT.Capability
  }

type State =
  { timeouts ∷ LT.Timeouts }

type LunaparkConstraints e m a
  = MonadError LE.Error m
  ⇒ MonadAff (ajax ∷ AJAX|e) m
  ⇒ MonadAsk Config m
  ⇒ MonadState State m
  ⇒ a

rethrow
  ∷ ∀ m e eff a
  . MonadThrow e m
  ⇒ MonadAff eff m
  ⇒ Aff eff (Either e a)
  → m a
rethrow a = liftAff a >>= either throwError pure

wrapEither ∷ ∀ m a. MonadThrow LE.Error m ⇒ Either String a → m a
wrapEither = either (throwError <<< LE.unknownError) pure

init
  ∷ ∀ e m
  . MonadAff (ajax ∷ AJAX|e) m
  ⇒ String
  → LT.CapabilitiesRequest
  → m (Either LE.Error LT.CreateSessionResponse)
init uri desiredCapabilities = do
  sessObj ← liftAff $ LA.init uri $ LT.encodeCapabilitiesRequest desiredCapabilities
  pure $ sessObj >>= \a → lmap LE.unknownError (LT.decodeCreateSessionResponse a)

quit ∷ ∀ e m. LunaparkConstraints e m (m Unit)
quit = do
  r ← ask
  void $ rethrow $ LA.quit r.baseURI $ un LT.SessionId r.session

status ∷ ∀ e m. LunaparkConstraints e m (m LT.ServerStatus)
status = do
  r ← ask
  res ← rethrow $ LA.status r.baseURI
  wrapEither $ LT.decodeServerStatus res

getTimeouts ∷ ∀ e m. LunaparkConstraints e m (m LT.Timeouts)
getTimeouts = do
  r ← ask
  res ← rethrow $ LA.getTimeouts r.baseURI $ un LT.SessionId r.session
  wrapEither $ LT.decodeTimeouts res

setTimeouts ∷ ∀ e m. LunaparkConstraints e m (LT.Timeouts → m Unit)
setTimeouts timeouts = do
  r ← ask
  void $ rethrow $ LA.setTimeouts
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeTimeouts timeouts)

go ∷ ∀ e m. LunaparkConstraints e m (String → m Unit)
go url = do
  r ← ask
  void $ rethrow $ LA.go
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeGoRequest url)

getCurrentUrl ∷ ∀ e m. LunaparkConstraints e m (m String)
getCurrentUrl = do
  r ← ask
  res ← rethrow $ LA.getCurrentUrl r.baseURI $ un LT.SessionId r.session
  wrapEither $ J.decodeJson res

back ∷ ∀ e m. LunaparkConstraints e m (m Unit)
back = do
  r ← ask
  void $ rethrow $ LA.back r.baseURI $ un LT.SessionId r.session

forward ∷ ∀ e m. LunaparkConstraints e m (m Unit)
forward = do
  r ← ask
  void $ rethrow $ LA.forward r.baseURI $ un LT.SessionId r.session

refresh ∷ ∀ e m. LunaparkConstraints e m (m Unit)
refresh = do
  r ← ask
  void $ rethrow $ LA.refresh r.baseURI $ un LT.SessionId r.session

getTitle ∷ ∀ e m. LunaparkConstraints e m (m String)
getTitle = do
  r ← ask
  res ← rethrow $ LA.getTitle r.baseURI $ un LT.SessionId r.session
  wrapEither $ J.decodeJson res

getWindowHandle ∷ ∀ e m. LunaparkConstraints e m (m LT.WindowHandle)
getWindowHandle = do
  r ← ask
  res ← rethrow $ LA.getWindowHandle r.baseURI $ un LT.SessionId r.session
  wrapEither $ LT.decodeWindowHandle res

closeWindow ∷ ∀ e m. LunaparkConstraints e m (m Unit)
closeWindow = do
  r ← ask
  void $ rethrow $ LA.closeWindow r.baseURI $ un LT.SessionId r.session

switchToWindow ∷ ∀ e m. LunaparkConstraints e m (LT.WindowHandle → m Unit)
switchToWindow wh = do
  r ← ask
  void $ rethrow $ LA.switchToWindow
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeSwitchToWindowRequest wh)

getWindowHandles ∷ ∀ e m. LunaparkConstraints e m (m (Array LT.WindowHandle))
getWindowHandles = do
  r ← ask
  res ← rethrow $ LA.getWindowHandles r.baseURI $ un LT.SessionId r.session
  wrapEither $ T.traverse LT.decodeWindowHandle =<< J.decodeJson res

switchToFrame ∷ ∀ e m. LunaparkConstraints e m (LT.FrameId → m Unit)
switchToFrame fid = do
  r ← ask
  void $ rethrow $ LA.switchToFrame
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeFrameId fid)

switchToParentFrame ∷ ∀ e m. LunaparkConstraints e m (m Unit)
switchToParentFrame = do
  r ← ask
  void $ rethrow $ LA.switchToParentFrame r.baseURI $ un LT.SessionId r.session

getWindowRect ∷ ∀ e m. LunaparkConstraints e m (m LT.Rectangle)
getWindowRect = do
  r ← ask
  res ← rethrow $ LA.getWindowRect r.baseURI $ un LT.SessionId r.session
  wrapEither $ LT.decodeRectangle res

setWindowRect ∷ ∀ e m. LunaparkConstraints e m (LT.Rectangle → m Unit)
setWindowRect rectangle = do
  r ← ask
  void $ rethrow $ LA.setWindowRect
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeRectangle rectangle)

maximizeWindow ∷ ∀ e m. LunaparkConstraints e m (m Unit)
maximizeWindow = do
  r ← ask
  void $ rethrow $ LA.maximizeWindow r.baseURI $ un LT.SessionId r.session

minimizeWindow ∷ ∀ e m. LunaparkConstraints e m (m Unit)
minimizeWindow = do
  r ← ask
  void $ rethrow $ LA.minimizeWindow r.baseURI $ un LT.SessionId r.session

fullscreenWindow ∷ ∀ e m. LunaparkConstraints e m (m Unit)
fullscreenWindow = do
  r ← ask
  void $ rethrow $ LA.fullscreenWindow r.baseURI $ un LT.SessionId r.session

findElement ∷ ∀ m e. LunaparkConstraints e m (LT.Locator → m LT.Element)
findElement loc = do
  r ← ask
  res ←
    rethrow $ LA.findElement
      r.baseURI
      (un LT.SessionId r.session)
      (LT.encodeLocator loc)
  wrapEither $ LT.decodeElement res

findElements ∷ ∀ m e. LunaparkConstraints e m (LT.Locator → m (Array LT.Element))
findElements loc = do
  r ← ask
  res ←
    rethrow $ LA.findElements
      r.baseURI
      (un LT.SessionId r.session)
      (LT.encodeLocator loc)
  wrapEither $ T.traverse LT.decodeElement =<< J.decodeJson res

findElementFromElement
  ∷ ∀ m e
  . LunaparkConstraints e m
  ( LT.Element
  → LT.Locator
  → m LT.Element
  )
findElementFromElement el loc = do
  r ← ask
  res ←
    rethrow $ LA.findElementFromElement
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
      (LT.encodeLocator loc)
  wrapEither $ LT.decodeElement res

findElementsFromElement
  ∷ ∀ m e
  . LunaparkConstraints e m
  ( LT.Element
  → LT.Locator
  → m (Array LT.Element)
  )
findElementsFromElement el loc = do
  r ← ask
  res ←
    rethrow $ LA.findElementsFromElement
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
      (LT.encodeLocator loc)
  wrapEither $ T.traverse LT.decodeElement =<< J.decodeJson res

getActiveElement ∷ ∀ m e. LunaparkConstraints e m (m LT.Element)
getActiveElement = do
  r ← ask
  res ← rethrow $ LA.getActiveElement r.baseURI $ un LT.SessionId r.session
  wrapEither $ LT.decodeElement res

isElementSelected ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m Boolean)
isElementSelected el = do
  r ← ask
  res ←
    rethrow $ LA.isElementSelected
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
  wrapEither $ J.decodeJson res

getElementAttribute ∷ ∀ m e. LunaparkConstraints e m (LT.Element → String → m (Maybe String))
getElementAttribute el attrName = do
  r ← ask
  res ←
    rethrow $ LA.getElementAttribute
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
      attrName
  if J.isNull res
    then pure Nothing
    else wrapEither $ J.decodeJson res

getElementProperty ∷ ∀ m e. LunaparkConstraints e m (LT.Element → String → m J.Json)
getElementProperty el propName = do
  r ← ask
  rethrow $ LA.getElementProperty
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)
    propName

getElementCSSValue ∷ ∀ m e. LunaparkConstraints e m (LT.Element → String → m String)
getElementCSSValue el cssName = do
  r ← ask
  res ←
    rethrow $ LA.getElementCSSValue
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
      cssName
  wrapEither $ J.decodeJson res

getElementText ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m String)
getElementText el = do
  r ← ask
  res ←
    rethrow $ LA.getElementText
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
  wrapEither $ J.decodeJson res

getElementTagName ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m String)
getElementTagName el = do
  r ← ask
  res ←
    rethrow $ LA.getElementTagName
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
  wrapEither $ J.decodeJson res

getElementRect ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m LT.Rectangle)
getElementRect el = do
  r ← ask
  res ←
    rethrow $ LA.getElementRect
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
  wrapEither $ LT.decodeRectangle res

isElementEnabled ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m Boolean)
isElementEnabled el = do
  r ← ask
  res ←
    rethrow $ LA.isElementEnabled
      r.baseURI
      (un LT.SessionId r.session)
      (un LT.Element el)
  wrapEither $ J.decodeJson res

elementClick ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m Unit)
elementClick el = do
  r ← ask
  void $ rethrow $ LA.elementClick
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)

elementClear ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m Unit)
elementClear el = do
  r ← ask
  void $ rethrow $ LA.elementClear
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)

elementSendKeys ∷ ∀ m e. LunaparkConstraints e m (LT.Element → String → m Unit)
elementSendKeys el txt = do
  r ← ask
  void $ rethrow $ LA.elementSendKeys
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)
    (LT.encodeSendKeysRequest txt)

getPageSource ∷ ∀ m e. LunaparkConstraints e m (m String)
getPageSource = do
  r ← ask
  res ← rethrow $ LA.getPageSource r.baseURI (un LT.SessionId r.session)
  wrapEither $ J.decodeJson res

executeScript ∷ ∀ m e. LunaparkConstraints e m (LT.Script → m J.Json)
executeScript scr = do
  r ← ask
  rethrow $ LA.executeScript
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeScript scr)

executeAsyncScript ∷ ∀ m e. LunaparkConstraints e m (LT.Script → m J.Json)
executeAsyncScript scr = do
  r ← ask
  rethrow $ LA.executeAsyncScript
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeScript scr)

getAllCookies ∷ ∀ m e. LunaparkConstraints e m (m (Array LT.Cookie))
getAllCookies = do
  r ← ask
  res ← rethrow $ LA.getAllCookies r.baseURI $ un LT.SessionId r.session
  wrapEither $ T.traverse LT.decodeCookie =<< J.decodeJson res

getNamedCookie ∷ ∀ m e. LunaparkConstraints e m (String → m LT.Cookie)
getNamedCookie name = do
  r ← ask
  res ← rethrow $ LA.getNamedCookie r.baseURI (un LT.SessionId r.session) name
  wrapEither $ LT.decodeCookie res

addCookie ∷ ∀ m e. LunaparkConstraints e m (LT.Cookie → m Unit)
addCookie cookie = do
  r ← ask
  void $ rethrow $ LA.addCookie
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeCookie cookie)

deleteCookie ∷ ∀ m e. LunaparkConstraints e m (String → m Unit)
deleteCookie name = do
  r ← ask
  void $ rethrow $ LA.deleteCookie
    r.baseURI
    (un LT.SessionId r.session)
    name

deleteAllCookies ∷ ∀ m e. LunaparkConstraints e m (m Unit)
deleteAllCookies = do
  r ← ask
  void $ rethrow $ LA.deleteAllCookies r.baseURI $ un LT.SessionId r.session

performActions ∷ ∀ m e. LunaparkConstraints e m (LT.ActionRequest → m Unit)
performActions req = do
  r ← ask
  void $ rethrow $ LA.performActions
    r.baseURI
    (un LT.SessionId r.session)
    (DT.spy $ LT.encodeActionRequest req)

releaseActions ∷ ∀ m e. LunaparkConstraints e m (m Unit)
releaseActions = do
  r ← ask
  void $ rethrow $ LA.releaseActions r.baseURI $ un LT.SessionId r.session

dismissAlert ∷ ∀ m e. LunaparkConstraints e m (m Unit)
dismissAlert = do
  r ← ask
  void $ rethrow $ LA.dismissAlert r.baseURI $ un LT.SessionId r.session

acceptAlert ∷ ∀ m e. LunaparkConstraints e m (m Unit)
acceptAlert = do
  r ← ask
  void $ rethrow $ LA.acceptAlert r.baseURI $ un LT.SessionId r.session

getAlertText ∷ ∀ m e. LunaparkConstraints e m (m String)
getAlertText = do
  r ← ask
  res ← rethrow $ LA.getAlertText r.baseURI $ un LT.SessionId r.session
  wrapEither $ J.decodeJson res

sendAlertText ∷ ∀ m e. LunaparkConstraints e m (String → m Unit)
sendAlertText s = do
  r ← ask
  void $ rethrow $ LA.sendAlertText
    r.baseURI
    (un LT.SessionId r.session)
    (LT.encodeSendKeysRequest s)

takeScreenshot ∷ ∀ m e. LunaparkConstraints e m (m LT.Screenshot)
takeScreenshot = do
  r ← ask
  res ← rethrow $ LA.takeScreenshot
    r.baseURI
    (un LT.SessionId r.session)
  wrapEither $ LT.decodeScreenshot res

takeElementScreenshot ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m LT.Screenshot)
takeElementScreenshot el = do
  r ← ask
  res ← rethrow $ LA.takeElementScreenshot
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)
  wrapEither $ LT.decodeScreenshot res

-- Recomended by W3C
isDisplayed ∷ ∀ m e. LunaparkConstraints e m (LT.Element → m Boolean)
isDisplayed el = do
  r ← ask
  res ← rethrow $ LA.isDisplayed
    r.baseURI
    (un LT.SessionId r.session)
    (un LT.Element el)
  wrapEither $ J.decodeJson res

-- JsonWire legacy
setWireTimeouts ∷ ∀ m e. LunaparkConstraints e m (LT.Timeouts → m Unit)
setWireTimeouts ts = do
  r ← ask
  T.for_ (LT.encodeLegacyTimeouts ts) \j →
    void $ rethrow $ LA.setTimeouts r.baseURI (un LT.SessionId r.session) j
-}
