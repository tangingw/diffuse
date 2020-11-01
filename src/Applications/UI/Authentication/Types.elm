module UI.Authentication.Types exposing (EncryptionMethod(..), Msg(..), Question, State(..))

import Html.Events.Extra.Mouse as Mouse
import Http
import Json.Decode as Json
import User.Layer exposing (Method(..))
import User.Layer.Methods.RemoteStorage as RemoteStorage



-- 🌳


type State
    = Authenticated Method
    | InputScreen Method Question
    | NewEncryptionScreen Method (Maybe EncryptionMethod) (Maybe String)
    | UpdateEncryptionScreen Method (Maybe EncryptionMethod) (Maybe String)
    | Unauthenticated
    | Welcome


type EncryptionMethod
    = Biometrics
    | Passphrase


type alias Question =
    { placeholder : String
    , question : String
    , value : String
    }



-- 📣


type Msg
    = Bypass
      --
    | BootFailure String
    | CancelFlow
    | GetStarted
    | NotAuthenticated
    | RemoteStorageWebfinger RemoteStorage.Attributes (Result Http.Error String)
    | ShowMoreOptions Mouse.Event
    | SignIn Method
    | SignInWithPassphrase Method String
    | SignedIn Json.Value
    | SignOut
    | TriggerExternalAuth Method String
      -----------------------------------------
      -- Encryption
      -----------------------------------------
    | KeepPassphraseInMemory String
    | MissingSecretKey Json.Value
    | RemoveEncryptionKey Method
    | ShowNewEncryptionScreen Method
    | ShowUpdateEncryptionScreen Method
    | UpdateEncryptionKey Method String
      -----------------------------------------
      -- IPFS
      -----------------------------------------
    | PingIpfs
    | PingIpfsCallback (Result Http.Error ())
    | PingOtherIpfs String
    | PingOtherIpfsCallback String (Result Http.Error ())
      -----------------------------------------
      -- More Input
      -----------------------------------------
    | AskForInput Method Question
    | Input String
    | ConfirmInput
