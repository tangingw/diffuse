module Brain.User.State exposing (..)

import Alien
import Brain.Common.State as Common
import Brain.Ports as Ports
import Brain.Types as Brain exposing (..)
import Brain.User.Types as User exposing (..)
import Debouncer.Basic as Debouncer
import EverySet
import Json.Decode as Decode
import Json.Encode as Json
import List.Zipper as Zipper
import Playlists.Encoding as Playlists
import Return exposing (andThen, return)
import Return.Ext as Return
import Settings
import Sources.Encoding as Sources
import Task
import Task.Extra exposing (do)
import Time
import Tracks exposing (Track)
import Tracks.Encoding as Tracks
import Tuple3
import Url exposing (Url)
import Url.Ext as Url
import User.Layer as User exposing (..)
import User.Layer.Methods.Dropbox as Dropbox
import User.Layer.Methods.Fission as Fission
import Webnative



-- 🌳


initialCommand : Url -> Cmd Brain.Msg
initialCommand uiUrl =
    case Url.action uiUrl of
        [ "authenticate", "fission" ] ->
            Cmd.none

        _ ->
            Cmd.batch
                [ do (UserMsg RetrieveMethod)
                , do (UserMsg RetrieveEnclosedData)
                ]



-- 📣


update : User.Msg -> Manager
update msg =
    case msg of
        SignIn a ->
            signIn a

        SignOut ->
            signOut

        -----------------------------------------
        -- 0. Secret Key
        -----------------------------------------
        FabricateSecretKey a ->
            fabricateSecretKey a

        SecretKeyFabricated ->
            secretKeyFabricated

        -----------------------------------------
        -- 1. Method
        -----------------------------------------
        RetrieveMethod ->
            retrieveMethod

        MethodRetrieved a ->
            methodRetrieved a

        -----------------------------------------
        -- 2. Data
        -----------------------------------------
        RetrieveHypaethralData a ->
            retrieveHypaethralData a

        HypaethralDataRetrieved a ->
            hypaethralDataRetrieved a

        -----------------------------------------
        -- 2. Data (Legacy)
        -----------------------------------------
        RetrieveLegacyHypaethralData ->
            retrieveLegacyHypaethralData

        -----------------------------------------
        -- x. Data
        -----------------------------------------
        RetrieveEnclosedData ->
            retrieveEnclosedData

        EnclosedDataRetrieved a ->
            enclosedDataRetrieved a

        SaveEnclosedData a ->
            saveEnclosedData a

        -----------------------------------------
        -- y. Data
        -----------------------------------------
        --   The hypaethral user data is received in pieces,
        --   pieces which are "cached" here in the web worker.
        --
        --   The reasons for this are:
        --   1. Lesser performance penalty on the UI when saving data
        --      (ie. this avoids having to encode/decode everything each time)
        --   2. The data can be used in the web worker (brain) as well.
        --      (eg. for track-search index)
        --
        SaveFavourites a ->
            saveFavourites a

        SavePlaylists a ->
            savePlaylists a

        SaveProgress a ->
            saveProgress a

        SaveSettings a ->
            saveSettings a

        SaveSources a ->
            saveSources a

        SaveTracks a ->
            saveTracks a

        -----------------------------------------
        -- z. Data
        -----------------------------------------
        GotWebnativeResponse a ->
            gotWebnativeResponse a

        SaveAllHypaethralData ->
            saveAllHypaethralData

        SaveHypaethralDataBit a ->
            saveHypaethralData a

        SaveHypaethralDataBits a ->
            saveHypaethralDataBits a

        SaveHypaethralDataSlowly a ->
            saveHypaethralDataSlowly a

        SaveNextHypaethralBit ->
            saveNextHypaethralBit

        -----------------------------------------
        -- z. Secret Key
        -----------------------------------------
        RemoveEncryptionKey ->
            removeEncryptionKey

        UpdateEncryptionKey a ->
            updateEncryptionKey a

        -----------------------------------------
        -- 📭 Other
        -----------------------------------------
        RefreshedDropboxTokens a b c ->
            refreshedDropboxTokens a b c



-- 🔱


gotWebnativeResponse : Webnative.Response -> Manager
gotWebnativeResponse response model =
    let
        baggage =
            model.hypaethralRetrieval
                |> Maybe.map (Zipper.current >> Tuple3.third)
                |> Maybe.withDefault BaggageClaimed
    in
    case Fission.proceed response baggage of
        Fission.Error err ->
            Common.reportUI Alien.ReportError err model

        Fission.Hypaethral data ->
            hypaethralDataRetrieved data model

        Fission.LoadedFileSystem ->
            -- Had to load the filesystem first, please continue.
            let
                authMethod =
                    Fission { initialised = True }
            in
            model.authMethod
                |> Maybe.map (\_ -> authMethod)
                |> (\a -> { model | authMethod = a })
                |> retrieveAllHypaethralData

        Fission.Ongoing newBaggage request ->
            model.hypaethralRetrieval
                |> Maybe.map
                    (newBaggage
                        |> always
                        |> Tuple3.mapThird
                        |> Zipper.map
                    )
                |> (\h -> { model | hypaethralRetrieval = h })
                |> Return.communicate (Ports.webnativeRequest request)

        Fission.OtherRequest request ->
            request
                |> Ports.webnativeRequest
                |> return model

        Fission.SaveNextHypaethralBit ->
            saveNextHypaethralBit model

        Fission.Stopping ->
            Return.singleton model


signIn : Json.Value -> Manager
signIn json model =
    -- 🐤
    -- Set & store method,
    -- and retrieve data.
    let
        decoder =
            Decode.map3
                (\a b c -> ( a, Maybe.withDefault False b, c ))
                (Decode.field "method" <| Decode.map methodFromString Decode.string)
                (Decode.field "migratingData" <| Decode.maybe Decode.bool)
                (Decode.field "passphrase" <| Decode.maybe Decode.string)
    in
    case Decode.decodeValue decoder json of
        Ok ( maybeMethod, migratingData, Just passphrase ) ->
            fabricateSecretKey
                passphrase
                { model
                    | authMethod = maybeMethod
                    , migratingData = migratingData
                    , performingSignIn = True
                }

        Ok ( maybeMethod, migratingData, Nothing ) ->
            { model
                | authMethod = maybeMethod
                , migratingData = migratingData
                , performingSignIn = True
            }
                |> (if migratingData then
                        hypaethralDataRetrieved Json.null

                    else
                        retrieveAllHypaethralData
                   )
                |> (case maybeMethod of
                        Just method ->
                            andThen (Common.giveUI Alien.AuthMethod <| encodeMethod method)

                        Nothing ->
                            identity
                   )

        _ ->
            Return.singleton model


signOut : Manager
signOut model =
    -- 💀
    -- Unset & remove stored method.
    [ Ports.removeCache (Alien.trigger Alien.AuthMethod)
    , Ports.removeCache (Alien.trigger Alien.AuthSecretKey)

    --
    , case model.authMethod of
        Just (Dropbox _) ->
            Cmd.none

        Just (Fission _) ->
            Ports.deconstructFission ()

        Just (Ipfs _) ->
            Cmd.none

        Just Local ->
            Cmd.none

        Just (RemoteStorage _) ->
            Ports.deconstructRemoteStorage ()

        Nothing ->
            Cmd.none
    ]
        |> Cmd.batch
        |> return
            { model
                | authMethod = Nothing
                , hypaethralUserData = emptyHypaethralData
            }



-- 🔱  ░░  DATA - ENCLOSED


enclosedDataRetrieved : Json.Value -> Manager
enclosedDataRetrieved json =
    Common.giveUI Alien.LoadEnclosedUserData json


retrieveEnclosedData : Manager
retrieveEnclosedData =
    Alien.AuthEnclosedData
        |> Alien.trigger
        |> Ports.requestCache
        |> Return.communicate


saveEnclosedData : Json.Value -> Manager
saveEnclosedData json =
    json
        |> Alien.broadcast Alien.AuthEnclosedData
        |> Ports.toCache
        |> Return.communicate



-- 🔱  ░░  DATA - HYPAETHRAL


hypaethralDataRetrieved : Json.Value -> Manager
hypaethralDataRetrieved encodedData model =
    if model.legacyMode then
        --------------
        -- Legacy Data
        --------------
        case Decode.decodeValue hypaethralDataDecoder encodedData of
            Ok decodedData ->
                { model | legacyMode = False }
                    |> sendHypaethralDataToUI encodedData decodedData
                    -- Save again in the new format
                    |> andThen saveAllHypaethralData
                    -- Show notification in UI thread
                    |> andThen (Common.nudgeUI Alien.ImportLegacyData)

            Err _ ->
                Return.singleton model

    else
        ---------------
        -- Default Flow
        ---------------
        let
            retrieval =
                Maybe.map
                    (Zipper.mapCurrent <| Tuple3.mapSecond <| always encodedData)
                    model.hypaethralRetrieval
        in
        case Maybe.andThen Zipper.next retrieval of
            Just nextRetrieval ->
                retrieveHypaethralData
                    (Tuple3.first <| Zipper.current nextRetrieval)
                    { model | hypaethralRetrieval = Just nextRetrieval }

            Nothing ->
                -- 🚀
                let
                    allJson =
                        retrieval
                            |> Maybe.map Zipper.toList
                            |> Maybe.withDefault []
                            |> putHypaethralJsonBitsTogether
                in
                { model
                    | hypaethralRetrieval = Nothing
                    , performingSignIn = False
                }
                    |> Return.singleton
                    |> Return.command
                        (case ( model.performingSignIn, model.authMethod ) of
                            ( True, Just method ) ->
                                method
                                    |> encodeMethod
                                    |> Alien.broadcast Alien.AuthMethod
                                    |> Ports.toCache

                            _ ->
                                Cmd.none
                        )
                    |> andThen
                        (model.authMethod
                            |> Maybe.map (\method -> Authenticated method allJson)
                            |> Maybe.map terminate
                            |> Maybe.withDefault Return.singleton
                        )


retrieveAllHypaethralData : Manager
retrieveAllHypaethralData model =
    let
        maybeZipper =
            hypaethralBit.list
                |> List.map (\( _, b ) -> ( b, Json.null, BaggageClaimed ))
                |> Zipper.fromList
    in
    case maybeZipper of
        Just zipper ->
            retrieveHypaethralData
                (Tuple3.first <| Zipper.current zipper)
                { model | hypaethralRetrieval = Just zipper }

        Nothing ->
            Return.singleton
                { model | hypaethralRetrieval = Nothing }


retrieveHypaethralData : HypaethralBit -> Manager
retrieveHypaethralData bit model =
    let
        filename =
            hypaethralBitFileName bit

        file =
            Json.string filename
    in
    case model.authMethod of
        -- 🚀
        Just (Dropbox { accessToken, expiresAt, refreshToken }) ->
            let
                currentTime =
                    Time.posixToMillis model.currentTime // 1000

                currentTimeWithOffset =
                    -- We add 60 seconds here because we only get the current time every minute,
                    -- so there's always the chance the "current time" is 1-60 seconds behind.
                    currentTime + 60
            in
            -- If the access token is expired
            if currentTimeWithOffset >= expiresAt then
                refreshToken
                    |> Dropbox.refreshAccessToken
                    |> Task.attempt
                        (\result ->
                            case result of
                                Ok tokens ->
                                    bit
                                        |> RetrieveHypaethralData
                                        |> RefreshedDropboxTokens
                                            { currentTime = currentTime
                                            , refreshToken = refreshToken
                                            }
                                            tokens
                                        |> UserMsg

                                Err err ->
                                    err
                                        |> Alien.report Alien.ReportError
                                        |> Ports.toUI
                                        |> Cmd
                        )
                    |> return model

            else
                [ ( "file", file )
                , ( "token", Json.string accessToken )
                ]
                    |> Json.object
                    |> Alien.broadcast Alien.AuthDropbox
                    |> Ports.requestDropbox
                    |> return model

        Just (Fission params) ->
            filename
                |> Fission.retrieve params bit
                |> Ports.webnativeRequest
                |> return model

        Just (Ipfs { apiOrigin }) ->
            [ ( "apiOrigin", Json.string apiOrigin )
            , ( "file", file )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthIpfs
                |> Ports.requestIpfs
                |> return model

        Just Local ->
            [ ( "file", file ) ]
                |> Json.object
                |> Alien.broadcast Alien.AuthAnonymous
                |> Ports.requestCache
                |> return model

        Just (RemoteStorage { userAddress, token }) ->
            [ ( "file", file )
            , ( "token", Json.string token )
            , ( "userAddress", Json.string userAddress )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthRemoteStorage
                |> Ports.requestRemoteStorage
                |> return model

        -- ✋
        Nothing ->
            Return.singleton model


retrieveLegacyHypaethralData : Manager
retrieveLegacyHypaethralData model =
    let
        file =
            Json.string "diffuse.json"
    in
    case model.authMethod of
        -- 🚀
        Just Local ->
            Alien.AuthAnonymous
                |> Alien.trigger
                |> Ports.requestLegacyLocalData
                |> return { model | legacyMode = True }

        Just (RemoteStorage { userAddress, token }) ->
            [ ( "file", file )
            , ( "token", Json.string token )
            , ( "userAddress", Json.string userAddress )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthRemoteStorage
                |> Ports.requestRemoteStorage
                |> return { model | legacyMode = True }

        -- ✋
        _ ->
            Return.singleton model


saveAllHypaethralData : Manager
saveAllHypaethralData =
    User.hypaethralBit.list
        |> List.map Tuple.second
        |> saveHypaethralDataBits


saveHypaethralData : HypaethralBit -> Manager
saveHypaethralData bit model =
    let
        filename =
            hypaethralBitFileName bit

        file =
            Json.string filename

        json =
            encodeHypaethralBit bit model.hypaethralUserData
    in
    case model.authMethod of
        -- 🚀
        Just (Dropbox { accessToken, expiresAt, refreshToken }) ->
            let
                currentTime =
                    Time.posixToMillis model.currentTime // 1000

                currentTimeWithOffset =
                    -- We add 60 seconds here because we only get the current time every minute,
                    -- so there's always the chance the "current time" is 1-60 seconds behind.
                    currentTime + 60
            in
            -- If the access token is expired
            if currentTimeWithOffset >= expiresAt then
                refreshToken
                    |> Dropbox.refreshAccessToken
                    |> Task.attempt
                        (\result ->
                            case result of
                                Ok tokens ->
                                    bit
                                        |> SaveHypaethralDataBit
                                        |> RefreshedDropboxTokens
                                            { currentTime = currentTime
                                            , refreshToken = refreshToken
                                            }
                                            tokens
                                        |> UserMsg

                                Err err ->
                                    err
                                        |> Alien.report Alien.ReportError
                                        |> Ports.toUI
                                        |> Cmd
                        )
                    |> return model

            else
                [ ( "data", json )
                , ( "file", file )
                , ( "token", Json.string accessToken )
                ]
                    |> Json.object
                    |> Alien.broadcast Alien.AuthDropbox
                    |> Ports.toDropbox
                    |> return model

        Just (Fission params) ->
            json
                |> Fission.save params bit filename
                |> List.map Ports.webnativeRequest
                |> Cmd.batch
                |> return model

        Just (Ipfs { apiOrigin }) ->
            [ ( "apiOrigin", Json.string apiOrigin )
            , ( "data", json )
            , ( "file", file )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthIpfs
                |> Ports.toIpfs
                |> return model

        Just Local ->
            [ ( "data", json )
            , ( "file", file )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthAnonymous
                |> Ports.toCache
                |> return model

        Just (RemoteStorage { userAddress, token }) ->
            [ ( "data", json )
            , ( "file", file )
            , ( "token", Json.string token )
            , ( "userAddress", Json.string userAddress )
            ]
                |> Json.object
                |> Alien.broadcast Alien.AuthRemoteStorage
                |> Ports.toRemoteStorage
                |> return model

        -- ✋
        Nothing ->
            Return.singleton model


{-| Save different parts of hypaethral data,
one part at a time.
-}
saveHypaethralDataBits : List HypaethralBit -> Manager
saveHypaethralDataBits bits model =
    let
        newItems =
            List.map (\b -> { bit = b, saving = False }) bits
    in
    case model.hypaethralStorage ++ newItems of
        item :: rest ->
            if item.saving then
                Return.singleton model

            else
                saveHypaethralData
                    item.bit
                    { model | hypaethralStorage = { item | saving = True } :: rest }

        _ ->
            Return.singleton model


saveHypaethralDataBitWithDebounce : HypaethralBit -> Manager
saveHypaethralDataBitWithDebounce bit =
    bit
        |> Debouncer.provideInput
        |> saveHypaethralDataSlowly


saveHypaethralDataSlowly : Debouncer.Msg HypaethralBit -> Manager
saveHypaethralDataSlowly debouncerMsg model =
    let
        ( m, c, e ) =
            Debouncer.update debouncerMsg model.hypaethralDebouncer

        bits =
            e
                |> Maybe.withDefault []
                |> EverySet.fromList
                |> EverySet.toList
    in
    c
        |> Cmd.map (SaveHypaethralDataSlowly >> UserMsg)
        |> return { model | hypaethralDebouncer = m }
        |> andThen (saveHypaethralDataBits bits)


{-| Saves some hypaethral data,
depending on what's in the queue saving queue
(ie. `hypaethralStorage`)
-}
saveNextHypaethralBit : Manager
saveNextHypaethralBit model =
    case model.hypaethralStorage of
        _ :: item :: rest ->
            saveHypaethralData
                item.bit
                { model | hypaethralStorage = { item | saving = True } :: rest }

        _ ->
            Return.singleton { model | hypaethralStorage = [] }


sendHypaethralDataToUI : Json.Value -> HypaethralData -> Manager
sendHypaethralDataToUI encodedData decodedData model =
    [ encodedData
        |> Alien.broadcast Alien.LoadHypaethralUserData
        |> Ports.toUI

    --
    , decodedData.tracks
        |> Json.list Tracks.encodeTrack
        |> Ports.updateSearchIndex
    ]
        |> Cmd.batch
        |> return { model | hypaethralUserData = decodedData }



-- 🔱  ░░  DATA - HYPAETHRAL BITS


saveFavourites : Json.Value -> Manager
saveFavourites value model =
    value
        |> Decode.decodeValue (Decode.list Tracks.favouriteDecoder)
        |> Result.withDefault model.hypaethralUserData.favourites
        |> hypaethralLenses.setFavourites model
        |> saveHypaethralDataBitWithDebounce Favourites


savePlaylists : Json.Value -> Manager
savePlaylists value model =
    value
        |> Decode.decodeValue (Decode.list Playlists.decoder)
        |> Result.withDefault model.hypaethralUserData.playlists
        |> hypaethralLenses.setPlaylists model
        |> saveHypaethralDataBitWithDebounce Playlists


saveProgress : Json.Value -> Manager
saveProgress value model =
    value
        |> Decode.decodeValue (Decode.dict Decode.float)
        |> Result.withDefault model.hypaethralUserData.progress
        |> hypaethralLenses.setProgress model
        |> saveHypaethralDataBitWithDebounce Progress


saveSettings : Json.Value -> Manager
saveSettings value model =
    value
        |> Decode.decodeValue (Decode.map Just Settings.decoder)
        |> Result.withDefault model.hypaethralUserData.settings
        |> hypaethralLenses.setSettings model
        |> saveHypaethralDataBitWithDebounce Settings


saveSources : Json.Value -> Manager
saveSources value model =
    value
        |> Decode.decodeValue (Decode.list Sources.decoder)
        |> Result.withDefault model.hypaethralUserData.sources
        |> hypaethralLenses.setSources model
        |> saveHypaethralDataBitWithDebounce Sources


saveTracks : Json.Value -> Manager
saveTracks value model =
    saveTracksAndUpdateSearchIndex
        (value
            |> Decode.decodeValue (Decode.list Tracks.trackDecoder)
            |> Result.withDefault model.hypaethralUserData.tracks
        )
        model


saveTracksAndUpdateSearchIndex : List Track -> Manager
saveTracksAndUpdateSearchIndex tracks model =
    tracks
        -- Store in model
        |> hypaethralLenses.setTracks model
        -- Update search index
        |> Return.communicate
            (tracks
                |> Json.list Tracks.encodeTrack
                |> Ports.updateSearchIndex
            )
        -- Save with delay
        |> andThen (saveHypaethralDataBitWithDebounce Tracks)



-- 🔱  ░░  DATA - HYPAETHRAL LENSES


hypaethralLenses =
    { setFavourites = makeHypaethralLens (\h f -> { h | favourites = f })
    , setPlaylists = makeHypaethralLens (\h p -> { h | playlists = p })
    , setProgress = makeHypaethralLens (\h p -> { h | progress = p })
    , setSettings = makeHypaethralLens (\h s -> { h | settings = s })
    , setSources = makeHypaethralLens (\h s -> { h | sources = s })
    , setTracks = makeHypaethralLens (\h t -> { h | tracks = t })
    }


makeHypaethralLens : (HypaethralData -> a -> HypaethralData) -> Model -> a -> Model
makeHypaethralLens setter model value =
    { model | hypaethralUserData = setter model.hypaethralUserData value }



-- 🔱  ░░  METHOD


methodRetrieved : Json.Value -> Manager
methodRetrieved json model =
    case decodeMethod json of
        -- 🚀
        Just method ->
            { model | authMethod = Just method }
                |> retrieveAllHypaethralData
                |> andThen (Common.giveUI Alien.AuthMethod <| encodeMethod method)

        -- ✋
        _ ->
            terminate NotAuthenticated model


refreshedDropboxTokens :
    { currentTime : Int, refreshToken : String }
    -> Dropbox.Tokens
    -> User.Msg
    -> Manager
refreshedDropboxTokens { currentTime, refreshToken } tokens msg model =
    { accessToken = tokens.accessToken
    , expiresAt = currentTime + tokens.expiresIn
    , refreshToken = refreshToken
    }
        |> Dropbox
        |> (\m -> saveMethod m model)
        |> andThen (update msg)


retrieveMethod : Manager
retrieveMethod =
    Alien.AuthMethod
        |> Alien.trigger
        |> Ports.requestCache
        |> Return.communicate


saveMethod : Method -> Manager
saveMethod method model =
    method
        |> encodeMethod
        |> Alien.broadcast Alien.AuthMethod
        |> Ports.toCache
        |> return { model | authMethod = Just method }



-- 🔱  ░░  SECRET KEY


fabricateSecretKey : String -> Manager
fabricateSecretKey passphrase =
    passphrase
        |> Json.string
        |> Alien.broadcast Alien.FabricateSecretKey
        |> Ports.fabricateSecretKey
        |> Return.communicate


removeEncryptionKey : Manager
removeEncryptionKey =
    [ Alien.AuthSecretKey
        |> Alien.trigger
        |> Ports.removeCache

    --
    , SaveAllHypaethralData
        |> UserMsg
        |> do
    ]
        |> Cmd.batch
        |> Return.communicate


secretKeyFabricated : Manager
secretKeyFabricated model =
    if model.performingSignIn then
        if model.migratingData then
            hypaethralDataRetrieved Json.null model

        else
            retrieveAllHypaethralData model

    else
        saveAllHypaethralData model


updateEncryptionKey : Json.Value -> Manager
updateEncryptionKey json =
    case Decode.decodeValue Decode.string json of
        Ok passphrase ->
            fabricateSecretKey passphrase

        Err _ ->
            Return.singleton



-- TERMINATION


type Termination
    = Authenticated Method Json.Value
    | NotAuthenticated


terminate : Termination -> Manager
terminate t model =
    case t of
        Authenticated method encodedData ->
            { model | migratingData = False }
                |> (if model.migratingData then
                        Return.singleton

                    else
                        encodedData
                            |> User.decodeHypaethralData
                            |> Result.withDefault model.hypaethralUserData
                            |> sendHypaethralDataToUI encodedData
                   )
                |> (encodeMethod method
                        |> Common.giveUI Alien.AuthMethod
                        |> andThen
                   )

        NotAuthenticated ->
            model
                |> Common.nudgeUI Alien.NotAuthenticated
                |> andThen (Common.nudgeUI Alien.HideLoadingScreen)
