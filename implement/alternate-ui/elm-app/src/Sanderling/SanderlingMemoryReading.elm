module Sanderling.SanderlingMemoryReading exposing
    ( ChildOfNodeWithDisplayRegion(..)
    , ContextMenu
    , ContextMenuEntry
    , DisplayRegion
    , InfoPanelRouteRouteElementMarker
    , MaybeVisible(..)
    , MemoryReadingUITreeNode
    , MemoryReadingUITreeNodeWithDisplayRegion
    , MemoryReadingWithNamedNodes
    , ShipManeuverType(..)
    , ShipUI
    , asUITreeNodeWithTotalDisplayRegion
    , canNotSeeItFromMaybeNothing
    , countDescendantsInUITreeNode
    , decodeMemoryReadingFromString
    , getDisplayText
    , getHorizontalOffsetFromParentAndWidth
    , getMostPopulousDescendantMatchingPredicate
    , getVerticalOffsetFromParent
    , listDescendantsInUITreeNode
    , listDescendantsWithDisplayRegion
    , maybeNothingFromCanNotSeeIt
    , memoryReadingUITreeNodeDecoder
    , parseContextMenusFromUITreeRoot
    , parseMemoryReadingWithNamedNodes
    , parseMemoryReadingWithNamedNodesFromJson
    , parseShipUIFromUITreeRoot
    , parseUITreeWithDisplayRegionFromUITree
    , unwrapMemoryReadingUITreeNodeChild
    )

import BigInt
import Dict
import Json.Decode
import Json.Encode


type alias MemoryReadingWithNamedNodes =
    { uiTree : MemoryReadingUITreeNodeWithDisplayRegion
    , shipUI : MaybeVisible ShipUI
    , contextMenus : List ContextMenu
    , infoPanelRoute : MaybeVisible InfoPanelRoute
    }


type alias MemoryReadingUITreeNodeWithDisplayRegion =
    { rawNode : MemoryReadingUITreeNode
    , children : Maybe (List ChildOfNodeWithDisplayRegion)
    , totalDisplayRegion : DisplayRegion
    }


type alias DisplayRegion =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


type ChildOfNodeWithDisplayRegion
    = ChildWithRegion MemoryReadingUITreeNodeWithDisplayRegion
    | ChildWithoutRegion MemoryReadingUITreeNode


type alias MemoryReadingUITreeNode =
    { originalJson : Json.Encode.Value
    , pythonObjectAddress : String
    , pythonObjectTypeName : String
    , dictEntriesOfInterest : Dict.Dict String Json.Encode.Value
    , children : Maybe (List MemoryReadingUITreeNodeChild)
    }


type MemoryReadingUITreeNodeChild
    = MemoryReadingUITreeNodeChild MemoryReadingUITreeNode


type alias ContextMenu =
    { uiElement : MemoryReadingUITreeNodeWithDisplayRegion
    , entries : List ContextMenuEntry
    }


type alias ContextMenuEntry =
    { uiElement : MemoryReadingUITreeNodeWithDisplayRegion
    , text : String
    }


type alias ShipUI =
    { uiElement : MemoryReadingUITreeNodeWithDisplayRegion
    , indication : MaybeVisible ShipUIIndication
    }


type alias ShipUIIndication =
    { maneuverType : MaybeVisible ShipManeuverType
    }


type ShipManeuverType
    = ManeuverWarp
    | ManeuverJump
    | ManeuverOrbit
    | ManeuverApproach


type alias InfoPanelRoute =
    { routeElementMarker : List InfoPanelRouteRouteElementMarker }


type alias InfoPanelRouteRouteElementMarker =
    { uiElement : MemoryReadingUITreeNodeWithDisplayRegion }


type MaybeVisible feature
    = CanNotSeeIt
    | CanSee feature


parseMemoryReadingWithNamedNodesFromJson : String -> Result String MemoryReadingWithNamedNodes
parseMemoryReadingWithNamedNodesFromJson =
    decodeMemoryReadingFromString
        >> Result.map (parseUITreeWithDisplayRegionFromUITree >> parseMemoryReadingWithNamedNodes)
        >> Result.mapError Json.Decode.errorToString


parseUITreeWithDisplayRegionFromUITree : MemoryReadingUITreeNode -> MemoryReadingUITreeNodeWithDisplayRegion
parseUITreeWithDisplayRegionFromUITree uiTree =
    uiTree |> asUITreeNodeWithTotalDisplayRegion (uiTree |> getDisplayRegionFromDictEntries |> Maybe.withDefault { x = 0, y = 0, width = 0, height = 0 })


parseMemoryReadingWithNamedNodes : MemoryReadingUITreeNodeWithDisplayRegion -> MemoryReadingWithNamedNodes
parseMemoryReadingWithNamedNodes uiTree =
    { uiTree = uiTree
    , shipUI = parseShipUIFromUITreeRoot uiTree
    , contextMenus = parseContextMenusFromUITreeRoot uiTree
    , infoPanelRoute = parseInfoPanelRouteFromUITreeRoot uiTree
    }


asUITreeNodeWithTotalDisplayRegion : DisplayRegion -> MemoryReadingUITreeNode -> MemoryReadingUITreeNodeWithDisplayRegion
asUITreeNodeWithTotalDisplayRegion totalDisplayRegion rawNode =
    { rawNode = rawNode
    , children = rawNode.children |> Maybe.map (List.map (unwrapMemoryReadingUITreeNodeChild >> asUITreeNodeWithInheritedOffset { x = totalDisplayRegion.x, y = totalDisplayRegion.y }))
    , totalDisplayRegion = totalDisplayRegion
    }


asUITreeNodeWithInheritedOffset : { x : Int, y : Int } -> MemoryReadingUITreeNode -> ChildOfNodeWithDisplayRegion
asUITreeNodeWithInheritedOffset inheritedOffset rawNode =
    case rawNode |> getDisplayRegionFromDictEntries of
        Nothing ->
            ChildWithoutRegion rawNode

        Just selfRegion ->
            ChildWithRegion
                (asUITreeNodeWithTotalDisplayRegion
                    { selfRegion | x = inheritedOffset.x + selfRegion.x, y = inheritedOffset.y + selfRegion.y }
                    rawNode
                )


getDisplayRegionFromDictEntries : MemoryReadingUITreeNode -> Maybe DisplayRegion
getDisplayRegionFromDictEntries uiElement =
    let
        fixedNumberFromJsonValue =
            Json.Encode.encode 0 >> parse64BitIntAndGetLower32BitInt >> Result.map .lower32Bit

        fixedNumberFromPropertyName propertyName =
            uiElement.dictEntriesOfInterest
                |> Dict.get propertyName
                |> Maybe.andThen (fixedNumberFromJsonValue >> Result.toMaybe)
    in
    case
        ( ( fixedNumberFromPropertyName "_displayX", fixedNumberFromPropertyName "_displayY" )
        , ( fixedNumberFromPropertyName "_displayWidth", fixedNumberFromPropertyName "_displayHeight" )
        )
    of
        ( ( Just displayX, Just displayY ), ( Just displayWidth, Just displayHeight ) ) ->
            Just { x = displayX, y = displayY, width = displayWidth, height = displayHeight }

        _ ->
            Nothing



-- Tests at https://ellie-app.com/7JJQTtHTJSwa1


parse64BitIntAndGetLower32BitInt :
    String
    -> Result String { valueAsBase16 : String, base16WithSignIntegrated : String, lower32Bit : Int }
parse64BitIntAndGetLower32BitInt asString =
    let
        ( wasNegative, valueAsString ) =
            if asString |> String.startsWith "-" then
                ( True, asString |> String.dropLeft 1 )

            else
                ( False, asString )
    in
    case valueAsString |> BigInt.fromIntString of
        Nothing ->
            Err "Failed to parse original as integer."

        Just valueAsBigInt ->
            let
                valueAsBase16 =
                    valueAsBigInt
                        |> BigInt.toHexString
                        |> String.padLeft 16 '0'
                        |> String.toLower

                withSignIntegratedResult =
                    if wasNegative then
                        valueAsBase16
                            |> String.map flipAllBitsInBase16Char
                            |> BigInt.fromHexString
                            |> Maybe.map (BigInt.add (BigInt.fromInt 1))

                    else
                        BigInt.fromHexString valueAsBase16
            in
            case withSignIntegratedResult of
                Nothing ->
                    Err "Failed fromHexString"

                Just withSignIntegrated ->
                    let
                        base16WithSignIntegrated =
                            withSignIntegrated
                                |> BigInt.toHexString
                                |> String.padLeft 16 '0'
                                |> String.toLower

                        lower32BitAsBase16 =
                            base16WithSignIntegrated |> String.right 8

                        lower32BitAsBigIntResult =
                            if lower32BitAsBase16 |> String.startsWith "f" then
                                lower32BitAsBase16
                                    |> String.map flipAllBitsInBase16Char
                                    |> BigInt.fromHexString
                                    |> Maybe.map (BigInt.add (BigInt.fromInt 1) >> BigInt.negate)

                            else
                                BigInt.fromHexString lower32BitAsBase16

                        lower32BitResult =
                            lower32BitAsBigIntResult
                                |> Maybe.andThen (BigInt.toString >> String.toInt)
                    in
                    case lower32BitResult of
                        Nothing ->
                            Err "Failed fromHexString"

                        Just lower32Bit ->
                            Ok
                                { valueAsBase16 = valueAsBase16
                                , base16WithSignIntegrated = base16WithSignIntegrated
                                , lower32Bit = lower32Bit
                                }


flipAllBitsInBase16Char : Char -> Char
flipAllBitsInBase16Char originalChar =
    case originalChar |> Char.toLower of
        '0' ->
            'f'

        '1' ->
            'e'

        '2' ->
            'd'

        '3' ->
            'c'

        '4' ->
            'b'

        '5' ->
            'a'

        '6' ->
            '9'

        '7' ->
            '8'

        '8' ->
            '7'

        '9' ->
            '6'

        'a' ->
            '5'

        'b' ->
            '4'

        'c' ->
            '3'

        'd' ->
            '2'

        'e' ->
            '1'

        'f' ->
            '0'

        _ ->
            '_'


parseContextMenusFromUITreeRoot : MemoryReadingUITreeNodeWithDisplayRegion -> List ContextMenu
parseContextMenusFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listChildrenWithDisplayRegion
            |> List.filter (.rawNode >> getNameFromDictEntries >> Maybe.map String.toLower >> (==) (Just "l_menu"))
            |> List.head
    of
        Nothing ->
            []

        Just layerMenu ->
            layerMenu
                |> listChildrenWithDisplayRegion
                |> List.filter (.rawNode >> .pythonObjectTypeName >> String.toLower >> String.contains "menu")
                |> List.map parseContextMenu


parseInfoPanelRouteFromUITreeRoot : MemoryReadingUITreeNodeWithDisplayRegion -> MaybeVisible InfoPanelRoute
parseInfoPanelRouteFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.rawNode >> .pythonObjectTypeName >> (==) "InfoPanelRoute")
            |> List.head
    of
        Nothing ->
            CanNotSeeIt

        Just infoPanelRouteElement ->
            let
                routeElementMarker =
                    infoPanelRouteElement
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.rawNode >> .pythonObjectTypeName >> (==) "AutopilotDestinationIcon")
                        |> List.map (\uiElement -> { uiElement = uiElement })
            in
            CanSee { routeElementMarker = routeElementMarker }


parseContextMenu : MemoryReadingUITreeNodeWithDisplayRegion -> ContextMenu
parseContextMenu contextMenuUIElement =
    let
        entriesUIElements =
            contextMenuUIElement
                |> listDescendantsWithDisplayRegion
                |> List.filter (.rawNode >> .pythonObjectTypeName >> String.toLower >> String.contains "menuentry")

        entries =
            entriesUIElements
                |> List.map
                    (\entryUIElement ->
                        let
                            text =
                                entryUIElement
                                    |> listDescendantsWithDisplayRegion
                                    |> List.filterMap (.rawNode >> getDisplayText)
                                    |> List.sortBy (String.length >> negate)
                                    |> List.head
                                    |> Maybe.withDefault ""
                        in
                        { text = text
                        , uiElement = entryUIElement
                        }
                    )
                |> List.sortBy (.uiElement >> .totalDisplayRegion >> .y)
    in
    { uiElement = contextMenuUIElement
    , entries = entries
    }


parseShipUIFromUITreeRoot : MemoryReadingUITreeNodeWithDisplayRegion -> MaybeVisible ShipUI
parseShipUIFromUITreeRoot uiTreeRoot =
    case
        uiTreeRoot
            |> listDescendantsWithDisplayRegion
            |> List.filter (.rawNode >> .pythonObjectTypeName >> (==) "ShipUI")
            |> List.head
    of
        Nothing ->
            CanNotSeeIt

        Just shipUIElement ->
            let
                speedGaugeElement =
                    shipUIElement
                        |> listDescendantsWithDisplayRegion
                        |> List.filter (.rawNode >> .pythonObjectTypeName >> (==) "SpeedGauge")
                        |> List.head

                maybeIndicationElement =
                    shipUIElement.rawNode
                        |> listDescendantsInUITreeNode
                        |> List.filter (getNameFromDictEntries >> Maybe.map (String.toLower >> String.contains "indicationcontainer") >> Maybe.withDefault False)
                        |> List.head

                indication =
                    maybeIndicationElement
                        |> Maybe.map (parseShipUIIndication >> CanSee)
                        |> Maybe.withDefault CanNotSeeIt
            in
            CanSee
                { uiElement = shipUIElement
                , indication = indication
                }


parseShipUIIndication : MemoryReadingUITreeNode -> ShipUIIndication
parseShipUIIndication indicationUIElement =
    let
        displayTexts =
            indicationUIElement |> getAllContainedDisplayTexts

        maneuverType =
            [ ( "Warp", ManeuverWarp )
            , ( "Jump", ManeuverJump )
            , ( "Orbit", ManeuverOrbit )
            , ( "Approach", ManeuverApproach )
            ]
                |> List.filterMap
                    (\( pattern, candidateManeuverType ) ->
                        if displayTexts |> List.any (String.contains pattern) then
                            Just candidateManeuverType

                        else
                            Nothing
                    )
                |> List.head
                |> canNotSeeItFromMaybeNothing
    in
    { maneuverType = maneuverType }


getDisplayText : MemoryReadingUITreeNode -> Maybe String
getDisplayText uiElement =
    [ "_setText", "_text" ]
        |> List.filterMap
            (\displayTextPropertyName ->
                uiElement.dictEntriesOfInterest
                    |> Dict.get displayTextPropertyName
                    |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.string >> Result.toMaybe)
            )
        |> List.sortBy (String.length >> negate)
        |> List.head


getAllContainedDisplayTexts : MemoryReadingUITreeNode -> List String
getAllContainedDisplayTexts uiElement =
    uiElement
        :: (uiElement |> listDescendantsInUITreeNode)
        |> List.filterMap getDisplayText


getNameFromDictEntries : MemoryReadingUITreeNode -> Maybe String
getNameFromDictEntries uiElement =
    uiElement.dictEntriesOfInterest
        |> Dict.get "_name"
        |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.string >> Result.toMaybe)


getHorizontalOffsetFromParentAndWidth : MemoryReadingUITreeNode -> Maybe { offset : Int, width : Int }
getHorizontalOffsetFromParentAndWidth uiElement =
    let
        roundedNumberFromPropertyName propertyName =
            uiElement.dictEntriesOfInterest
                |> Dict.get propertyName
                |> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
                |> Maybe.map round
    in
    case ( roundedNumberFromPropertyName "_displayX", roundedNumberFromPropertyName "_width" ) of
        ( Just offset, Just width ) ->
            Just { offset = offset, width = width }

        _ ->
            Nothing


getVerticalOffsetFromParent : MemoryReadingUITreeNode -> Maybe Int
getVerticalOffsetFromParent =
    .dictEntriesOfInterest
        >> Dict.get "_displayY"
        >> Maybe.andThen (Json.Decode.decodeValue Json.Decode.float >> Result.toMaybe)
        >> Maybe.map round


getMostPopulousDescendantMatchingPredicate : (MemoryReadingUITreeNode -> Bool) -> MemoryReadingUITreeNode -> Maybe MemoryReadingUITreeNode
getMostPopulousDescendantMatchingPredicate predicate parent =
    listDescendantsInUITreeNode parent
        |> List.filter predicate
        |> List.sortBy countDescendantsInUITreeNode
        |> List.reverse
        |> List.head


unwrapMemoryReadingUITreeNodeChild : MemoryReadingUITreeNodeChild -> MemoryReadingUITreeNode
unwrapMemoryReadingUITreeNodeChild child =
    case child of
        MemoryReadingUITreeNodeChild node ->
            node


countDescendantsInUITreeNode : MemoryReadingUITreeNode -> Int
countDescendantsInUITreeNode parent =
    parent.children
        |> Maybe.withDefault []
        |> List.map unwrapMemoryReadingUITreeNodeChild
        |> List.map (countDescendantsInUITreeNode >> (+) 1)
        |> List.sum


listDescendantsInUITreeNode : MemoryReadingUITreeNode -> List MemoryReadingUITreeNode
listDescendantsInUITreeNode parent =
    parent.children
        |> Maybe.withDefault []
        |> List.map unwrapMemoryReadingUITreeNodeChild
        |> List.concatMap (\child -> child :: listDescendantsInUITreeNode child)


listDescendantsWithDisplayRegion : MemoryReadingUITreeNodeWithDisplayRegion -> List MemoryReadingUITreeNodeWithDisplayRegion
listDescendantsWithDisplayRegion parent =
    parent
        |> listChildrenWithDisplayRegion
        |> List.concatMap (\child -> child :: listDescendantsWithDisplayRegion child)


listChildrenWithDisplayRegion : MemoryReadingUITreeNodeWithDisplayRegion -> List MemoryReadingUITreeNodeWithDisplayRegion
listChildrenWithDisplayRegion parent =
    parent.children
        |> Maybe.withDefault []
        |> List.filterMap
            (\child ->
                case child of
                    ChildWithoutRegion _ ->
                        Nothing

                    ChildWithRegion childWithRegion ->
                        Just childWithRegion
            )


decodeMemoryReadingFromString : String -> Result Json.Decode.Error MemoryReadingUITreeNode
decodeMemoryReadingFromString =
    Json.Decode.decodeString memoryReadingUITreeNodeDecoder


memoryReadingUITreeNodeDecoder : Json.Decode.Decoder MemoryReadingUITreeNode
memoryReadingUITreeNodeDecoder =
    Json.Decode.map5
        (\originalJson pythonObjectAddress pythonObjectTypeName dictEntriesOfInterest children ->
            { originalJson = originalJson
            , pythonObjectAddress = pythonObjectAddress
            , pythonObjectTypeName = pythonObjectTypeName
            , dictEntriesOfInterest = dictEntriesOfInterest |> Dict.fromList
            , children = children |> Maybe.map (List.map MemoryReadingUITreeNodeChild)
            }
        )
        Json.Decode.value
        (Json.Decode.field "pythonObjectAddress" Json.Decode.value |> Json.Decode.map (Json.Encode.encode 0))
        (decodeOptionalField "pythonObjectTypeName" Json.Decode.string |> Json.Decode.map (Maybe.withDefault ""))
        (Json.Decode.field "dictEntriesOfInterest" (Json.Decode.keyValuePairs Json.Decode.value))
        (decodeOptionalOrNullField "children" (Json.Decode.list (Json.Decode.lazy (\_ -> memoryReadingUITreeNodeDecoder))))


decodeOptionalOrNullField : String -> Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
decodeOptionalOrNullField fieldName decoder =
    decodeOptionalField fieldName (Json.Decode.nullable decoder)
        |> Json.Decode.map (Maybe.andThen identity)


decodeOptionalField : String -> Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
decodeOptionalField fieldName decoder =
    let
        finishDecoding json =
            case Json.Decode.decodeValue (Json.Decode.field fieldName Json.Decode.value) json of
                Ok val ->
                    -- The field is present, so run the decoder on it.
                    Json.Decode.map Just (Json.Decode.field fieldName decoder)

                Err _ ->
                    -- The field was missing, which is fine!
                    Json.Decode.succeed Nothing
    in
    Json.Decode.value
        |> Json.Decode.andThen finishDecoding


canNotSeeItFromMaybeNothing : Maybe a -> MaybeVisible a
canNotSeeItFromMaybeNothing maybe =
    case maybe of
        Nothing ->
            CanNotSeeIt

        Just feature ->
            CanSee feature


maybeNothingFromCanNotSeeIt : MaybeVisible a -> Maybe a
maybeNothingFromCanNotSeeIt maybeVisible =
    case maybeVisible of
        CanNotSeeIt ->
            Nothing

        CanSee feature ->
            Just feature
