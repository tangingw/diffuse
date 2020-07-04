module UI.Playlists.Directory exposing (generate)

import Dict exposing (Dict)
import List.Extra as List
import Playlists exposing (..)
import Set exposing (Set)
import Sources exposing (Source)
import String.Ext as String
import Tracks exposing (Track)



-- 🔱


generate : List Source -> List Track -> List Playlist
generate sources tracks =
    let
        sourceDirectories =
            List.foldl
                (\s ->
                    if s.enabled && s.directoryPlaylists then
                        s.data
                            |> Dict.get "directoryPath"
                            |> Maybe.map fixPath
                            |> Maybe.withDefault ""
                            |> Dict.insert s.id

                    else
                        identity
                )
                Dict.empty
                sources

        playlistNames =
            List.foldr
                (reducer sourceDirectories)
                Set.empty
                tracks
    in
    playlistNames
        |> Set.toList
        |> List.map
            (\n ->
                { autoGenerated = True
                , name = n
                , tracks = []
                }
            )


fixPath : String -> String
fixPath string =
    string
        |> String.chopStart "/"
        |> (\s ->
                if String.isEmpty s || String.endsWith "/" s then
                    s

                else
                    s ++ "/"
           )



-- ㊙️


reducer : Dict String String -> Track -> Set String -> Set String
reducer sourceDirectories track =
    case Dict.get track.sourceId sourceDirectories of
        Just prefix ->
            let
                path =
                    String.dropLeft (String.length prefix) track.path
            in
            case String.split "/" path of
                a :: _ :: _ ->
                    Set.insert a

                _ ->
                    identity

        Nothing ->
            identity
