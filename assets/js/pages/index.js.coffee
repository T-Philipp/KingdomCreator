#= require lib/all.js
#= require pages/page.js.coffee
#= require randomizer/randomizer.js.coffee
#= require randomizer/serializer.js.coffee
#= require settings/settings-manager.js.coffee
#= require viewmodels/card.js.coffee
#= require viewmodels/dialog.js.coffee
#= require viewmodels/metadata.js.coffee
#= require viewmodels/set.js.coffee

do ->
   CardViewModel = window.CardViewModel
   DialogViewModel = window.DialogViewModel
   MetadataViewModel = window.MetadataViewModel
   PageViewModel = window.PageViewModel
   SetViewModel = window.SetViewModel
   SettingsManager = window.SettingsManager

   Randomizer = window.Randomizer
   Serializer = window.Serializer

   SUBTITLE = 'Dominion randomizer for desktop and mobile'

   class IndexViewModel extends PageViewModel
      constructor: (dominionSets) ->
         super(SUBTITLE, PageViewModel.MenuItem.RANDOMIZER)
         @dominionSets = dominionSets
         @kingdom = null
         @sets = ko.observableArray(@createSetViewModels())
         @cards = ko.observableArray(new CardViewModel(@) for i in [0...10])
         @eventsAndLandmarks = ko.observableArray(new CardViewModel(@, false) for i in [0...2])
         
         # Load settings from cookie.
         @settings = null
         @randomizerSettings = null
         @loadOptionsFromSettings()

         @isEnlarged = ko.observable(false)
         @metadata = new MetadataViewModel()
         @dialog = new DialogViewModel(@sets())
         @hasLoaded = ko.observable(false)
         @showEventsAndLandmarks = @createShowEventsAndLandmarksObservable()
         @eventsAndLandmarksHeader = @createEventsAndLandmarksHeaderObservable()
         @randomizeButtonText = @createRandomizeButtonTextObservable()
         @loadCardBacks()
         @loadInitialKingdom()

      loadInitialKingdom: () =>
         resultFromUrl = Serializer.deserializeKingdom(@dominionSets, location.search)
         if resultFromUrl
            if resultFromUrl.kingdom.cards.length == 10
               @setKingdomAndMetadata(resultFromUrl.kingdom, resultFromUrl.metadata)
               return

            # Randomize the rest of the set if there are less than 10 cards.
            result = Randomizer.createKingdom(@dominionSets, {
               setIds: (set.id for set in @sets() when set.active()),
               excludeTypes: @getExcludeTypes()
               includeCardIds: (card.id for card in resultFromUrl.kingdom.cards)
               includeEventIds: (event.id for event in resultFromUrl.kingdom.events)
               includeLandmarkIds: (landmark.id for landmark in resultFromUrl.kingdom.landmarks)
               requireActionProvider: @randomizerSettings.requireActionProvider()
               requireBuyProvider: @randomizerSettings.requireBuyProvider()
               requireReactionIfAttackCards: @randomizerSettings.requireReaction()
               requireTrashing: @randomizerSettings.requireTrashing()
               fillKingdomEventsAndLandmarks: 
                  !resultFromUrl.kingdom.events.length and !resultFromUrl.kingdom.landmarks.length
            })
            @setKingdomAndMetadata(result.kingdom, resultFromUrl.metadata)
            return

         @randomize()

      randomize: () =>
         selectedCards = @getSelectedCards()

         if (selectedCards.length > 1 or
               @getSelectedEvents().length or
               @getSelectedLandmarks().length or
               @getSelectedUndefinedEventOrLandmarkIds().length)
            @randomizeSelectedCards()
            return

         # Show a dialog for customizing when randomizing a single card for specifying the card.
         if selectedCards.length == 1
            dialogOptions = {typeStates: {}}
            @dialog.open(dialogOptions, @randomizeIndividualSelectedCard)
            return

         @randomizeFullKingdom()

      randomizeFullKingdom: ->
         setIds = (set.id for set in @sets() when set.active())
         card.setToLoading() for card in @cards()
         card.setToLoading() for card in @eventsAndLandmarks()

         # Bail if no sets are selected.
         return unless setIds.length

         result = Randomizer.createKingdom(@dominionSets, {
            setIds: setIds,
            excludeCardIds: @getCardsToExclude()
            excludeTypes: @getExcludeTypes()
            requireActionProvider: @randomizerSettings.requireActionProvider()
            requireBuyProvider: @randomizerSettings.requireBuyProvider()
            requireReactionIfAttackCards: @randomizerSettings.requireReaction()
            requireTrashing: @randomizerSettings.requireTrashing()
            fillKingdomEventsAndLandmarks: true
         })
         @setKingdomAndMetadata(result.kingdom, result.metadata)
         @saveSettings()

      randomizeSelectedCards: =>
         result = Randomizer.createKingdom(@dominionSets, {
            setIds: (set.id for set in @sets() when set.active()),
            includeCardIds: @extractCardIds(@getUnselectedCards())
            excludeCardIds: @extractCardIds(@getSelectedCards())
            includeEventIds: (event.id for event in @kingdom.events)
            includeLandmarkIds: (landmark.id for landmark in @kingdom.landmarks)
            requireActionProvider: @randomizerSettings.requireActionProvider()
            requireBuyProvider: @randomizerSettings.requireBuyProvider()
            requireReactionIfAttackCards: @randomizerSettings.requireReaction()
            requireTrashing: @randomizerSettings.requireTrashing()
            eventIdsToReplace:
               @extractCardIds(@getSelectedEvents()).concat(@getSelectedUndefinedEventOrLandmarkIds())
            landmarkIdsToReplace: @extractCardIds(@getSelectedLandmarks())
            fillKingdomEventsAndLandmarks: false
         })
         @replaceSelectedCardsWithKingdom(result.kingdom) if result

      randomizeIndividualSelectedCard: =>
         excludeTypes = []
         if @dialog.selectedType() == Randomizer.Type.NONE and !@randomizerSettings.allowAttacks()
            excludeTypes.push(Randomizer.Type.ATTACK)

         result = Randomizer.createKingdom(@dominionSets, {
            setIds: (ko.unwrap(set.id) for set in @dialog.sets when set.active())
            includeCardIds: @extractCardIds(@getUnselectedCards())
            excludeCardIds: @extractCardIds(@getSelectedCards())
            excludeTypes: excludeTypes
            includeEventIds: (event.id for event in @kingdom.events)
            includeLandmarkIds: (landmark.id for landmark in @kingdom.landmarks)
            requiredType: @dialog.selectedType()
            allowedCosts: (ko.unwrap(costs.id) for costs in @dialog.costs when costs.active())
            requireActionProvider: @randomizerSettings.requireActionProvider()
            requireBuyProvider: @randomizerSettings.requireBuyProvider()
            requireReactionIfAttackCards: @randomizerSettings.requireReaction()
            requireTrashing: @randomizerSettings.requireTrashing()
            eventIdsToReplace:
               @extractCardIds(@getSelectedEvents()).concat(@getSelectedUndefinedEventOrLandmarkIds())
            landmarkIdsToReplace: @extractCardIds(@getSelectedLandmarks())
            fillKingdomEventsAndLandmarks: false
         })
         @replaceSelectedCardsWithKingdom(result.kingdom) if result
      

      replaceSelectedCardsWithKingdom: (kingdom) ->
         selectedCards = @getSelectedCards()
         nonSelectedCardIds = @extractCardIds(@getUnselectedCards())
         selectedEvents = @getSelectedEvents()
         selectedLandmarks = @getSelectedLandmarks()
         selectedUndefinedEventOrLandmark = @getSelectedUndefinedEventOrLandmark()
         nonSelectedEventAndLandmarkIds =
            (ko.unwrap(card.id) for card in @eventsAndLandmarks() when !card.selected()) 
         
         # Set cards to loading and get the new cards.
         card.setToLoading() for card in selectedCards
         card.setToLoading() for card in selectedEvents
         card.setToLoading() for card in selectedLandmarks
         card.setToLoading() for card in selectedUndefinedEventOrLandmark

         @kingdom = kingdom
         @updateUrlForKingdom(@kingdom, {
            useColonies: @metadata.useColonies()
            useShelters: @metadata.useShelters()
         })
         sets = @sets()
         imagesLeftToLoad = selectedCards.length + selectedEvents.length + selectedLandmarks.length
         
         # Use this function to sync all of the images so that the sort
         # only happens after all have loaded.
         registerComplete = => 
            if --imagesLeftToLoad <= 0 
               setTimeout((=> @sortCards()), CardViewModel.ANIMATION_TIME)
         
         setCardData = (card, data) =>
            card.setData(data, sets)
            if card.cardImageLoaded()
               registerComplete()
            else
               # Capture the subscription so we can dispose after the image loads.
               do =>
                  subscription = card.cardImageLoaded.subscribe (val) =>
                     return unless val
                     subscription.dispose()
                     registerComplete()

         nextSelectedCardIndex = 0
         for cardData in @kingdom.cards
            if (nonSelectedCardIds.indexOf(cardData.id) == -1 and
                  nextSelectedCardIndex < selectedCards.length)
               setCardData(selectedCards[nextSelectedCardIndex++], cardData)

         nextIndex = 0
         selectedEventsAndLandmarks =
            selectedEvents.concat(selectedLandmarks).concat(selectedUndefinedEventOrLandmark)
         eventsAndLandmarks = @kingdom.events.concat(@kingdom.landmarks)
         for cardData in eventsAndLandmarks
            if (nonSelectedEventAndLandmarkIds.indexOf(cardData.id) == -1 and
                  nextIndex < selectedEventsAndLandmarks.length)
               setCardData(selectedEventsAndLandmarks[nextIndex++], cardData)
      
      setKingdomAndMetadata: (kingdom, metadata) ->
         @kingdom = kingdom
         @kingdom.cards.sort(@cardSorter)

         cards = @cards()
         sets = @sets()
         for card, index in @kingdom.cards
            cards[index].setData(card, sets)
         for eventOrLandmark, index in @eventsAndLandmarks()
            if index < @kingdom.events.length
               eventOrLandmark.setData(@kingdom.events[index], sets)
               continue
            landmarkIndex = index - @kingdom.events.length
            if landmarkIndex < @kingdom.landmarks.length
               eventOrLandmark.setData(@kingdom.landmarks[landmarkIndex], sets)
               continue
            else
               eventOrLandmark.setToLoading()

         @metadata.update(metadata)
         @updateUrlForKingdom(kingdom, metadata)

      toggleEnlarged: ->
         @isEnlarged(!@isEnlarged())

      createSetViewModels:  ->
         sets = (set for setId, set of @dominionSets)
         sets.sort (a, b) ->
            return 0 if a.name == b.name
            return if a.name < b.name then -1 else 1

         return (new SetViewModel(set) for set in sets)

      createShowEventsAndLandmarksObservable: ->
         return ko.computed =>
            return false unless @hasLoaded()
            for setViewModel in ko.unwrap(@sets)
               if ko.unwrap(setViewModel.active)
                  set = @dominionSets[ko.unwrap(setViewModel.id)]
                  if set.events?.length or set.landmarks?.length
                     return true

            # Check if the current kingdom has any events or landmarks.
            for eventOrLandmark in @eventsAndLandmarks()
               if !ko.unwrap(eventOrLandmark.isLoading)
                  return true
            return false

      createEventsAndLandmarksHeaderObservable: ->
         return ko.computed =>
            hasEvents = false
            hasLandmarks = false
            for setViewModel in ko.unwrap(@sets)
               if ko.unwrap(setViewModel.active)
                  set = @dominionSets[ko.unwrap(setViewModel.id)]
                  hasEvents = true if set.events?.length
                  hasLandmarks = true if set.landmarks?.length

            # Check if the current kingdom has any events or landmarks.
            for eventOrLandmark in @eventsAndLandmarks()
               id = ko.unwrap(eventOrLandmark.id)
               hasEvents = true if id and id.indexOf('_event_') != -1
               hasLandmarks = true if id and id.indexOf('_landmark_') != -1
            
            return 'Events and Landmarks' if hasEvents and hasLandmarks
            return 'Events' if hasEvents
            return 'Landmarks' if hasLandmarks
            return ''

      createRandomizeButtonTextObservable: ->
         return ko.computed =>
            allCards = @cards().concat(@eventsAndLandmarks())
            for card in allCards
               return 'Replace!' if card.selected()
            return 'Randomize!'

      loadOptionsFromSettings: =>
         @settings = SettingsManager.loadSettings()
         @randomizerSettings = @settings.randomizerSettings()

         # Set the active state of the sets.
         selectedSets = @settings.selectedSets()
         for set in @sets()
            set.active(selectedSets.indexOf(set.id) != -1)
            set.active.subscribe(@saveSettings)

         # Resort the cards when the sort option changes.
         @settings.sortAlphabetically.subscribe(@sortCards)

         # Save the settings when settings change.
         @settings.sortAlphabetically.subscribe(@saveSettings)
         @settings.showSetOnCards.subscribe(@saveSettings)
         @randomizerSettings.requireActionProvider.subscribe(@saveSettings)
         @randomizerSettings.requireBuyProvider.subscribe(@saveSettings)
         @randomizerSettings.allowAttacks.subscribe(@saveSettings)
         @randomizerSettings.requireReaction.subscribe(@saveSettings)
         @randomizerSettings.requireTrashing.subscribe(@saveSettings)

      saveSettings: () =>
         selectedSets = (set.id for set in @sets() when set.active())
         @settings.selectedSets(selectedSets)
         SettingsManager.saveSettings(@settings)

      getCardsToExclude: ->
         numberOfCardsInSelectedSets = 0
         setIds = (set.id for set in @sets() when set.active())
         return [] if setIds.length < 3
         return @extractCardIds(@cards())

      getExcludeTypes: ->
         types = []
         types.push(Randomizer.Type.ATTACK) unless @randomizerSettings.allowAttacks()
         return types

      extractCardIds: (cards) ->
         return (ko.unwrap(card.id) for card in cards)

      getSelectedCards: ->
         return (card for card in @cards() when card.selected())

      getUnselectedCards: ->
         return (card for card in @cards() when !card.selected())

      getSelectedEvents: ->
         selectedEvents = []
         for card in @eventsAndLandmarks()
            id = ko.unwrap(card.id)
            if id and id.indexOf('_event_') != -1 and ko.unwrap(card.selected)
               selectedEvents.push(card)

         return selectedEvents

      getSelectedLandmarks: ->
         selectedLandmarks = []
         for card in @eventsAndLandmarks()
            id = ko.unwrap(card.id)
            if id and id.indexOf('_landmark_') != -1 and ko.unwrap(card.selected)
               selectedLandmarks.push(card)
         return selectedLandmarks

      getSelectedUndefinedEventOrLandmark: ->
         selectedUndefinedEventOrLandmark = []
         for card in @eventsAndLandmarks()
            if ko.unwrap(card.isLoading) and ko.unwrap(card.selected)
               selectedUndefinedEventOrLandmark.push(card)
         return selectedUndefinedEventOrLandmark

      getSelectedUndefinedEventOrLandmarkIds: ->
         selectedUndefinedEventOrLandmarkIds = []
         for card in @getSelectedUndefinedEventOrLandmark()
            selectedUndefinedEventOrLandmarkIds.push('undefined_event_or_landmark')
         return selectedUndefinedEventOrLandmarkIds

      updateUrlForKingdom: (kingdom, metadata) ->
         url = new URL(location.href)
         url.search = Serializer.serializeKingdom(kingdom, metadata)
         history.replaceState({}, '', url.href)

      loadCardBacks: => 
         start = Date.now()
         remaining = 2
         handleLoaded = =>
            return unless --remaining == 0
            if (left = 500 - (Date.now() - start)) > 0
               setTimeout (=> @hasLoaded(true)), left
            else @hasLoaded(true)
         $.imgpreload(CardViewModel.VERTICAL_LOADING_IMAGE_URL, handleLoaded)
         $.imgpreload(CardViewModel.HORIZONTAL_LOADING_IMAGE_URL, handleLoaded)

      sortCards: =>
         isEnlarged = @isEnlarged() and @isCondensed()
         $body = $('body')
         cards = @cards()
         $cards = $('#cards').find('.card-wrap .card-front')
         pairs = []
         for card, index in cards
            pairs.push({ card: card, element: $($cards[index]) })
         
         pairs.sort(@cardPairSorter)
         
         movedPairs = []
         for pair, pairIndex in pairs
            for card, cardIndex in cards
               if card == pair.card and pairIndex != cardIndex
                  pair.movedFrom = pair.element.offset()
                  pair.movedTo = $($cards[pairIndex]).offset()
                  movedPairs.push(pair)
            
         for p in movedPairs
            do (pair = p) ->
               pair.clone = pair.element.clone(false)
               tX = pair.movedTo.left - pair.movedFrom.left
               tY = pair.movedTo.top - pair.movedFrom.top
               setVenderProp = (obj, prop, val) ->
                  obj['-webkit-'+prop] = val
                  obj['-moz-'+prop] = val
                  obj[prop] = val
                  return obj

               # Build all the css required
               css = {
                  position: 'absolute'
                  height: pair.element.height()
                  width: pair.element.width()
                  top: pair.movedFrom.top
                  left: pair.movedFrom.left
                  'z-index': 250
                  'transition-property': '-webkit-transform, -webkit-filter, opacity'
                  'transition-property': '-moz-transform, -moz-filter, opacity'
               }
               
               setVenderProp(css, 'transition-timing-function', 'ease-in-out')
               setVenderProp(css, 'transition-duration', '600ms')
               setVenderProp(css, 'transition-delay', 0)
               setVenderProp(css, 'filter', 'none')
               setVenderProp(css, 'transition', 'transform 600ms ease-in-out')
               setVenderProp(css, 'transform', "translate(0px,0px)")

               # Set up everything for the animation
               pair.clone.addClass('enlarge-cards') if isEnlarged
               pair.clone.appendTo($body).css(css)
               pair.element.css('visibility', 'hidden')
               pair.clone.bind 'webkitTransitionEnd transitionend otransitionend oTransitionEnd', ->
                  pair.element.css('visibility', 'visible')
                  pair.clone.remove()
               
               # This timeout is required so that the animation actually takes place
               setTimeout ->
                  pair.clone.css(setVenderProp({}, 'transform', "translate(#{tX}px,#{tY}px)"))
               , 0

         # Sort all the cards while the ones that will change position are moving
         @cards.sort(@cardSorter)

      cardPairSorter: (a, b) => return @cardSorter(a.card, b.card)
      cardSorter: (a, b) =>
         unless @settings.sortAlphabetically()
            return -1 if ko.unwrap(a.setId) < ko.unwrap(b.setId)
            return 1 if ko.unwrap(a.setId) > ko.unwrap(b.setId)
         return -1 if ko.unwrap(a.name) < ko.unwrap(b.name)
         return 1 if ko.unwrap(a.name) > ko.unwrap(b.name)
         return 0


   window.IndexViewModel = IndexViewModel