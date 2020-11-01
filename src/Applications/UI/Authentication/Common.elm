module UI.Authentication.Common exposing (..)

import UI.Authentication.Types exposing (..)
import User.Layer exposing (Method)



-- 🛠


extractMethod : State -> Maybe Method
extractMethod state =
    case state of
        Authenticated method ->
            Just method

        InputScreen method _ ->
            Just method

        NewEncryptionScreen method _ _ ->
            Just method

        UpdateEncryptionScreen method _ _ ->
            Just method

        Unauthenticated ->
            Nothing

        Welcome ->
            Nothing
