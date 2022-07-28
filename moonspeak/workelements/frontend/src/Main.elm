port module Main exposing (..)

import Browser exposing (Document)
import Css
import Debug exposing (log)
import Dict exposing (Dict)
import Html exposing (Attribute, Html, button, div, input, li, ol, span, text)
import Html.Attributes exposing (attribute, class, placeholder, style, value)
import Html.Events exposing (on, onClick, onInput)
import Html.Events.Extra exposing (targetValueIntParse)
import Html.Lazy exposing (lazy, lazy2)
import Http
import Json.Decode as D
import Json.Encode as E
import List.Extra
import Platform.Cmd as Cmd
import Url.Builder exposing (relative)



-- PORTS


port sendMessage : E.Value -> Cmd msg


port messageReceiver : (D.Value -> msg) -> Sub msg



-- MAIN


main =
    Browser.document
        { init = init
        , subscriptions = subscriptions
        , update = update
        , view = view
        }



-- MODEL


type alias KeyCandidate =
    { word : String
    , metadata : String
    , freq : List Int
    }


type alias Frequency =
    List Int


type alias WorkElement =
    { kanji : String
    , keyword : String
    , notes : String
    }


type alias Model =
    { currentWork : WorkElement
    , workElements : List WorkElement
    , currentWorkIndex : Int
    , freq : List Int
    , userMessages : Dict String String
    , onSubmitFailIndex : Int
    }


defaultCurrentWork =
    WorkElement "" "" ""


brokenCurrentWork =
    WorkElement "X" "Error" "An error occurred"


defaultModel =
    { currentWork = defaultCurrentWork
    , workElements = []
    , currentWorkIndex = 0
    , freq = []
    , userMessages = Dict.empty
    , onSubmitFailIndex = 0
    }


defaultModelTwo =
    { defaultModel | workElements = [ WorkElement "a" "first" "", WorkElement "b" "" "asd", WorkElement "c" "third" "and comment" ] }


init : () -> ( Model, Cmd Msg )
init _ =
    -- ( model, Cmd.none )
    ( defaultModel, getWorkElements )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    messageReceiver RecvNewElementValue


keywordEncoder : String -> E.Value
keywordEncoder keyword =
    E.object
        [ ( "keyword", E.string keyword ) ]


portEncoder : WorkElement -> E.Value
portEncoder elem =
    E.object
        [ ( "kanji", E.string elem.kanji )
        , ( "keyword", E.string elem.keyword )
        , ( "notes", E.string elem.notes )
        ]


type alias MsgDecoded =
    { keyword : String, kanji : String, notes : String }


portDecoder : D.Decoder MsgDecoded
portDecoder =
    D.map3 MsgDecoded
        (D.field "keyword" D.string)
        (D.field "kanji" D.string)
        (D.field "notes" D.string)



-- UPDATE


type Msg
    = SelectWorkElement Int
    | RecvNewElementValue D.Value
      -- work element manipulations
    | KeywordInput String
    | NotesInput String
    | ElementSubmitClick
      -- Http responses
    | WorkElementsReady (Result Http.Error (List WorkElement))
    | ElementSubmitReady (Result Http.Error String)
    | KeywordCheckReady (Result Http.Error KeyCandidate)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        WorkElementsReady result ->
            case result of
                Ok elements ->
                    let
                        newModel =
                            { model | workElements = elements }
                    in
                    update (SelectWorkElement newModel.currentWorkIndex) newModel

                Err httpError ->
                    -- HTTP error: do nothing, just report
                    let
                        message =
                            buildErrorMessage httpError

                        newUserMessages =
                            Dict.insert "WorkElementsReady" message model.userMessages

                        newModel =
                            { model | userMessages = newUserMessages }
                    in
                    ( newModel, Cmd.none )

        SelectWorkElement index ->
            let
                selected =
                    Maybe.withDefault
                        (WorkElement "X" "Error" "An error occurred")
                        (List.Extra.getAt index model.workElements)

                newModel =
                    { model | currentWorkIndex = index, currentWork = selected }

                cmd =
                    Cmd.batch
                        [ getKeywordCheck newModel.currentWork.kanji newModel.currentWork.keyword
                        , sendMessage (portEncoder newModel.currentWork)
                        ]
            in
            ( newModel, cmd )

        RecvNewElementValue jsonValue ->
            case D.decodeValue portDecoder jsonValue of
                Ok value ->
                    let
                        -- update current element
                        updatedElement =
                            WorkElement value.kanji value.keyword value.notes

                        updatedWorkElements =
                            List.Extra.setAt model.currentWorkIndex updatedElement model.workElements

                        -- select the next work element to display
                        index =
                            model.currentWorkIndex + 1

                        currentElement =
                            Maybe.withDefault
                                (WorkElement "X" "Error" "An error occurred")
                                (List.Extra.getAt index model.workElements)

                        newModel =
                            { model
                                | workElements = updatedWorkElements
                                , currentWorkIndex = index
                                , currentWork = currentElement
                                , onSubmitFailIndex = model.currentWorkIndex
                                , userMessages = Dict.empty
                            }

                        cmd =
                            Cmd.batch
                                [ submitElement updatedElement
                                , sendMessage (portEncoder currentElement)
                                , getKeywordCheck currentElement.kanji currentElement.keyword
                                ]
                    in
                    -- post to backend and send the message with next work element
                    ( newModel, cmd )

                Err _ ->
                    ( model, Cmd.none )

        ElementSubmitReady result ->
            case result of
                Ok body ->
                    if String.length body > 0 then
                        -- logical error: refresh all elements from db
                        let
                            message =
                                "Error submitting keyword. Details:" ++ body

                            newUserMessages =
                                Dict.insert "ElementSubmitReady" message model.userMessages

                            newModel =
                                { model | userMessages = newUserMessages, currentWorkIndex = model.onSubmitFailIndex }
                        in
                        ( newModel, getWorkElements )

                    else
                        -- submit went ok: do nothing
                        -- the model has already been updated and the message has already been sent
                        ( model, Cmd.none )

                Err httpError ->
                    -- HTTP error: do nothing, just report
                    let
                        message =
                            buildErrorMessage httpError

                        newUserMessages =
                            Dict.insert "ElementSubmitReady" message model.userMessages

                        newModel =
                            { model | userMessages = newUserMessages }
                    in
                    ( newModel, Cmd.none )

        ElementSubmitClick ->
            if String.length model.currentWork.keyword > 0 then
                let
                    -- update current elements array
                    updatedWorkElements =
                        List.Extra.setAt model.currentWorkIndex model.currentWork model.workElements

                    -- select the next work element to display
                    index =
                        model.currentWorkIndex + 1

                    currentElement =
                        Maybe.withDefault
                            (WorkElement "X" "Error" "An error occurred")
                            (List.Extra.getAt index model.workElements)

                    newModel =
                        { model
                            | workElements = updatedWorkElements
                            , currentWorkIndex = index
                            , currentWork = currentElement
                            , onSubmitFailIndex = model.currentWorkIndex
                            , userMessages = Dict.empty
                        }

                    cmd =
                        Cmd.batch
                            [ submitElement model.currentWork
                            , sendMessage (portEncoder currentElement)
                            , getKeywordCheck currentElement.kanji currentElement.keyword
                            ]
                in
                -- send post request and message the world with new work element
                ( newModel, cmd )

            else
                ( { model | userMessages = Dict.insert "ElementSubmitClick" "Error: keyword length must be non-zero" model.userMessages }, Cmd.none )

        KeywordInput word ->
            let
                current =
                    model.currentWork

                newCurrentWork =
                    { current | keyword = word }

                newModel =
                    { model | currentWork = newCurrentWork }

                cmd =
                    Cmd.batch
                        [ getKeywordCheck newCurrentWork.kanji newCurrentWork.keyword
                        , sendMessage (keywordEncoder newCurrentWork.keyword)
                        ]
            in
            if String.length word >= 2 then
                ( newModel, cmd )

            else
                ( { newModel | freq = [], userMessages = Dict.empty }, Cmd.none )

        NotesInput word ->
            let
                current =
                    model.currentWork

                newCurrentWork =
                    { current | notes = word }

                newModel =
                    { model | currentWork = newCurrentWork }
            in
            ( newModel, Cmd.none )

        KeywordCheckReady result ->
            case result of
                Ok elem ->
                    ( { model | freq = elem.freq, userMessages = Dict.insert "KeywordCheckReady" elem.metadata model.userMessages }, Cmd.none )

                Err _ ->
                    ( { model | freq = [], userMessages = Dict.insert "KeywordCheckReady" "Error getting keyword frequency" model.userMessages }, Cmd.none )


buildErrorMessage : Http.Error -> String
buildErrorMessage httpError =
    case httpError of
        Http.BadUrl message ->
            message

        Http.Timeout ->
            "Server is taking too long to respond. Please try again later."

        Http.NetworkError ->
            "Unable to reach server."

        Http.BadStatus statusCode ->
            "Request failed with status code: " ++ String.fromInt statusCode

        Http.BadBody message ->
            message


getKeywordCheck : String -> String -> Cmd Msg
getKeywordCheck kanji keyword =
    Http.get
        { url = relative [ "api", "keywordcheck/" ++ kanji ++ "/" ++ keyword ] []
        , expect = Http.expectJson KeywordCheckReady keyCandidateDecoder
        }


keyCandidateDecoder : D.Decoder KeyCandidate
keyCandidateDecoder =
    D.map3 KeyCandidate
        (D.field "word" D.string)
        (D.field "metadata" D.string)
        (D.field "freq" (D.list D.int))


getWorkElements : Cmd Msg
getWorkElements =
    Http.get
        { url = relative [ "api", "work" ] []
        , expect = Http.expectJson WorkElementsReady workElementsDecoder
        }


workElementsDecoder : D.Decoder (List WorkElement)
workElementsDecoder =
    D.list
        (D.map3 WorkElement
            (D.index 0 D.string)
            (D.index 1 D.string)
            (D.index 2 D.string)
        )


submitElement : WorkElement -> Cmd Msg
submitElement element =
    Http.post
        { url = relative [ "api", "submit" ] []
        , body = Http.jsonBody (submitElementEncoder element)
        , expect = Http.expectString ElementSubmitReady
        }


submitElementEncoder : WorkElement -> E.Value
submitElementEncoder element =
    E.object
        [ ( "kanji", E.string element.kanji )
        , ( "keyword", E.string element.keyword )
        , ( "notes", E.string element.notes )
        ]



-- VIEW


view : Model -> Document Msg
view model =
    Document "workelements" [ render model ]


renderSubmitBar : WorkElement -> Frequency -> Html Msg
renderSubmitBar currentWork freq =
    div [ style "display" "flex" ]
        [ span
            [ style "flex" "1 0 auto" ]
            [ text currentWork.kanji ]
        , span
            [ style "flex" "10 0 70px" ]
            [ input
                [ placeholder "Keyword"
                , value currentWork.keyword
                , onInput KeywordInput
                , style "width" "100%"
                , style "box-sizing" "border-box"
                ]
                []
            ]
        , span
            [ style "flex" "1 0 auto" ]
            [ text ("Corpus: " ++ (String.fromInt <| Maybe.withDefault 0 <| List.Extra.getAt 0 freq)) ]
        , span
            [ style "flex" "1 0 auto" ]
            [ text ("Subs: " ++ (String.fromInt <| Maybe.withDefault 0 <| List.Extra.getAt 1 freq)) ]
        , span
            [ style "flex" "1 0 auto" ]
            [ button [ onClick ElementSubmitClick ] [ text "Submit" ] ]
        , span
            [ style "flex" "10 0 70px" ]
            [ input
                [ placeholder "Notes"
                , value currentWork.notes
                , onInput NotesInput
                , style "width" "100%"
                , style "box-sizing" "border-box"
                ]
                []
            ]
        ]


renderSingleWorkElement : Int -> WorkElement -> Html Msg
renderSingleWorkElement index elem =
    div
        [ style "padding" "2px 0"
        , style "display" "flex"
        , class "row"
        ]
        [ span
            [ style "flex" "0 0 1.5rem"
            , value (String.fromInt index)
            ]
            [ text (String.fromInt index ++ ".") ]
        , span
            [ style "flex" "0 0 auto"
            , style "margin" "0 0.5rem"
            ]
            [ text elem.kanji ]
        , span
            [ style "flex" "1 0 4rem"
            , style "margin" "0 0.5rem"
            , if String.length elem.keyword > 0 then
                style "background-color" "rgb(200, 210, 200)"

              else
                style "background-color" ""
            ]
            [ text elem.keyword ]
        , span
            [ style "flex" "10 1 auto"
            , if String.length elem.notes > 0 then
                style "background-color" "rgb(200, 200, 210)"

              else
                style "background-color" ""
            ]
            [ text elem.notes ]
        ]


renderWorkElements : Model -> Html Msg
renderWorkElements model =
    let
        partial =
            lazy2 renderSingleWorkElement
    in
    div
        [ on "click" (D.map SelectWorkElement targetValueIntParse)
        ]
        (List.indexedMap partial model.workElements)


renderUserMessages : Model -> Html Msg
renderUserMessages model =
    div [] [ text (String.join "!" (Dict.values model.userMessages)) ]


render : Model -> Html Msg
render model =
    div
        [ style "background-color" "rgb(210, 210, 210)"
        , style "overflow" "auto"
        ]
        [ lazy renderUserMessages model
        , lazy2 div [] [ text "Work Elements" ]
        , lazy2 renderSubmitBar model.currentWork model.freq
        , lazy renderWorkElements model
        ]
