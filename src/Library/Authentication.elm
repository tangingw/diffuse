module Authentication exposing (EnclosedUserData, HypaethralUserData, Method(..), decode, decodeMethod, decoder, emptyHypaethralUserData, encodeMethod, methodFromString, methodToString)

import Json.Decode as Json
import Json.Decode.Pipeline exposing (optional)
import Json.Encode
import Maybe.Extra as Maybe
import Sources
import Sources.Encoding as Sources
import Tracks
import Tracks.Encoding as Tracks



-- 🌳


type Method
    = Ipfs
    | Local


type alias EnclosedUserData =
    {}


type alias HypaethralUserData =
    { favourites : List Tracks.Favourite
    , sources : List Sources.Source
    , tracks : List Tracks.Track
    }



-- 🔱


emptyHypaethralUserData : HypaethralUserData
emptyHypaethralUserData =
    { favourites = []
    , sources = []
    , tracks = []
    }


methodToString : Method -> String
methodToString method =
    case method of
        Ipfs ->
            "IPFS"

        Local ->
            "LOCAL"


methodFromString : String -> Maybe Method
methodFromString string =
    case string of
        "IPFS" ->
            Just Ipfs

        "LOCAL" ->
            Just Local

        _ ->
            Nothing



-- 🔱  ░░  DECODING & ENCODING


decode : Json.Value -> Result Json.Error HypaethralUserData
decode =
    Json.decodeValue decoder


decodeMethod : Json.Value -> Maybe Method
decodeMethod =
    Json.decodeValue (Json.map methodFromString Json.string) >> Result.toMaybe >> Maybe.join


decoder : Json.Decoder HypaethralUserData
decoder =
    Json.succeed HypaethralUserData
        |> optional "favourites" (Json.list Tracks.favouriteDecoder) []
        |> optional "sources" (Json.list Sources.decoder) []
        |> optional "tracks" (Json.list Tracks.trackDecoder) []


encodeMethod : Method -> Json.Value
encodeMethod =
    methodToString >> Json.Encode.string
