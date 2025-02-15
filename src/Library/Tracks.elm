module Tracks exposing (..)

import Base64
import List.Extra as List
import Playlists exposing (Playlist, PlaylistTrack)
import String.Ext as String
import Time
import Time.Ext as Time



-- 🌳


type alias Track =
    { id : String
    , insertedAt : Time.Posix
    , path : String
    , sourceId : String
    , tags : Tags
    }



-- PIECES


type alias Tags =
    { disc : Int
    , nr : Int

    -- Main
    , album : String
    , artist : String
    , title : String

    -- Extra
    , genre : Maybe String
    , picture : Maybe String
    , year : Maybe Int
    }



-- DERIVATIVES & SUPPLEMENTS


type alias Cover =
    { group : String
    , identifiedTrackCover : IdentifiedTrack
    , key : String
    , sameAlbum : Bool
    , sameArtist : Bool
    , trackIds : List String
    , tracks : List IdentifiedTrack
    , variousArtists : Bool
    }


type alias Favourite =
    { artist : String
    , title : String
    }


type alias IdentifiedTrack =
    ( Identifiers, Track )


type alias Identifiers =
    { isFavourite : Bool
    , isMissing : Bool

    --
    , filename : String
    , group : Maybe { name : String, firstInGroup : Bool }
    , indexInList : Int
    , indexInPlaylist : Maybe Int
    , parentDirectory : String
    }



-- COLLECTIONS


type alias Collection =
    { untouched : List Track

    -- `Track`s with `Identifiers`
    , identified : List IdentifiedTrack

    -- Sorted, grouped and filtered by playlist (if not auto-generated)
    , arranged : List IdentifiedTrack

    -- Filtered by search results, favourites, etc.
    , harvested : List IdentifiedTrack

    -- Contexts
    -----------
    , scrollContext : String
    }


type alias CollectionDependencies =
    { cached : List String
    , cachedOnly : Bool
    , enabledSourceIds : List String
    , favourites : List Favourite
    , favouritesOnly : Bool
    , grouping : Maybe Grouping
    , hideDuplicates : Bool
    , selectedPlaylist : Maybe Playlist
    , searchResults : Maybe (List String)
    , sortBy : SortBy
    , sortDirection : SortDirection
    }


type alias Parcel =
    ( CollectionDependencies, Collection )


type alias CoverCollection =
    { arranged : List Cover
    , harvested : List Cover
    }



-- GROUPING & SORTING


type Grouping
    = AddedOn
    | Directory
    | FirstAlphaCharacter
    | TrackYear


type SortBy
    = Artist
    | Album
    | PlaylistIndex
    | Title


type SortDirection
    = Asc
    | Desc



-- VIEW


type Scene
    = Covers
    | List



-- 🔱


emptyTrack : Track
emptyTrack =
    { id = ""
    , insertedAt = Time.default
    , path = ""
    , sourceId = ""
    , tags = emptyTags
    }


emptyTags : Tags
emptyTags =
    { disc = 1
    , nr = 0
    , album = "Empty"
    , artist = "Empty"
    , title = "Empty"
    , genre = Nothing
    , picture = Nothing
    , year = Nothing
    }


emptyIdentifiedTrack : IdentifiedTrack
emptyIdentifiedTrack =
    ( emptyIdentifiers
    , emptyTrack
    )


emptyIdentifiers : Identifiers
emptyIdentifiers =
    { isFavourite = False
    , isMissing = False

    --
    , filename = ""
    , group = Nothing
    , indexInList = 0
    , indexInPlaylist = Nothing
    , parentDirectory = ""
    }


emptyCollection : Collection
emptyCollection =
    { untouched = []
    , identified = []
    , arranged = []
    , harvested = []

    -- Contexts
    -----------
    , scrollContext = ""
    }



-- MORE STUFF


isNowPlaying : IdentifiedTrack -> IdentifiedTrack -> Bool
isNowPlaying ( a, b ) ( x, y ) =
    a.indexInPlaylist == x.indexInPlaylist && b.id == y.id


makeTrack : String -> ( String, Tags ) -> Track
makeTrack sourceId ( path, tags ) =
    { id =
        (sourceId ++ "//" ++ path)
            |> Base64.encode
            |> String.chopEnd "="
    , insertedAt = Time.default
    , path = path
    , sourceId = sourceId
    , tags = tags
    }


missingAlbumPlaceholder : String
missingAlbumPlaceholder =
    "⌁"


pathParts : Track -> { filename : String, parentDirectory : String }
pathParts { path } =
    let
        s =
            String.split "/" path

        l =
            List.length s
    in
    case List.drop (max 0 <| l - 2) s of
        [ p, f ] ->
            { filename = f, parentDirectory = p }

        [ f ] ->
            { filename = f, parentDirectory = "" }

        _ ->
            { filename = "", parentDirectory = "" }


{-| Given a collection of tracks, pick out the tracks by id in order.
Note that track ids in the ids list may occur multiple times.
-}
pick : List String -> List Track -> List Track
pick ids collection =
    collection
        |> List.foldr
            (\track ->
                List.map
                    (\picking ->
                        case picking of
                            PickId id ->
                                if id == track.id then
                                    PickTrack track

                                else
                                    PickId id

                            p ->
                                p
                    )
            )
            (List.map PickId ids)
        |> List.foldr
            (\picking acc ->
                case picking of
                    PickId _ ->
                        acc

                    PickTrack track ->
                        track :: acc
            )
            []


removeByPaths : { sourceId : String, paths : List String } -> List Track -> { kept : List Track, removed : List Track }
removeByPaths { sourceId, paths } tracks =
    tracks
        |> List.foldr
            (\t ( kept, removed, remainingPathsToRemove ) ->
                if t.sourceId == sourceId && List.member t.path remainingPathsToRemove then
                    ( kept, t :: removed, List.remove t.path remainingPathsToRemove )

                else
                    ( t :: kept, removed, remainingPathsToRemove )
            )
            ( [], [], paths )
        |> (\( k, r, _ ) ->
                { kept = k, removed = r }
           )


removeBySourceId : String -> List Track -> { kept : List Track, removed : List Track }
removeBySourceId removedSourceId tracks =
    tracks
        |> List.foldr
            (\t ( kept, removed ) ->
                if t.sourceId == removedSourceId then
                    ( kept, t :: removed )

                else
                    ( t :: kept, removed )
            )
            ( [], [] )
        |> (\( k, r ) ->
                { kept = k, removed = r }
           )


removeFromPlaylist : List IdentifiedTrack -> Playlist -> Playlist
removeFromPlaylist tracks playlist =
    playlist.tracks
        |> List.indexedFoldr
            (\idx t ( acc, remaining ) ->
                case List.partition ((==) (Just idx)) remaining of
                    ( _ :: _, rem ) ->
                        ( acc, rem )

                    ( _, rem ) ->
                        ( t :: acc, rem )
            )
            ( []
            , List.map (Tuple.first >> .indexInPlaylist) tracks
            )
        |> (\( t, _ ) -> { playlist | tracks = t })


missingId : String
missingId =
    "<missing>"


shouldRenderGroup : Identifiers -> Bool
shouldRenderGroup identifiers =
    identifiers.group
        |> Maybe.map (.firstInGroup >> (==) True)
        |> Maybe.withDefault False


toPlaylistTracks : List IdentifiedTrack -> List PlaylistTrack
toPlaylistTracks =
    List.map
        (\( _, t ) ->
            { album = t.tags.album
            , artist = t.tags.artist
            , title = t.tags.title
            }
        )



-- ㊙️


type Pick
    = PickId String
    | PickTrack Track
