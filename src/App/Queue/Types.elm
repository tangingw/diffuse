module Queue.Types exposing (..)

import Date exposing (Date)
import Html5.DragDrop as DragDrop
import Sources.Types exposing (Source)
import Tracks.Types exposing (Track, TrackId)


-- Messages


type Msg
    = InjectFirst Track InjectOptions
    | InjectLast Track InjectOptions
    | RemoveItem Int
      -- Position
    | Rewind
    | Shift
      -- Contents
    | Fill Date (List Track)
    | Clear
    | Clean (List Track)
    | Reset
      -- Combos
    | InjectFirstAndPlay Track
      -- Settings
    | ToggleRepeat
    | ToggleShuffle
      -- Libraries
    | DragDropMsg (DragDrop.Msg Int Int)



-- Model


type alias Model =
    InternalModel Settings


type alias InternalModel extension =
    { extension
        | activeItem : Maybe Item
        , dnd : DragDrop.Model Int Int
        , future : List Item
        , ignored : List Item
        , past : List Item
    }


type alias Settings =
    { repeat : Bool
    , shuffle : Bool
    }



-- Items


type alias Item =
    { manualEntry : Bool
    , track : Track
    }


type alias EngineItem =
    { track : Track
    , url : String
    }



-- Routing


type Page
    = Index
    | History



-- Other


type alias InjectOptions =
    { showNotification : Bool }
