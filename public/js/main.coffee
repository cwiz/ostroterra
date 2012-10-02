#
# Main shit
#

serp = null
serpRows = null

main = () ->
  
  # defaults

  $.datepicker.setDefaults $.datepicker.regional["ru"]

  serp = new SocketSERP 

    showStatistics: () ->
      serpRows.rows[0].showStats()
      serpRows.calculateStatistics()
      serpRows.rows[0].showStats()
      
    
    onHotelsReady: (data) ->
      if not (data.signature is serpRows.currentSignature)
        return
      
      neededRow = serpRows.rows[data.rowNumber]
      neededRow.addHotels data.hotels
      
      @showStatistics()
    
    onFlightsReady: (data) ->
      if not (data.signature is serpRows.currentSignature)
        return      

      neededRow = serpRows.rows[data.rowNumber]
      neededRow.addFlights data.flights

      @showStatistics()

  serpRows  = new SearchRowCollection
  
  # --- 1st row default values
  firstRow  = new SearchRow
  serpRows.push firstRow

  firstRow.calendar.attr      'placeholder', 'когда'
  firstRow.autocomplete.attr  'placeholder', 'откуда'

  firstRow.showTeaser()

  # --- 2nd row
  secondRow = new SearchRow
  serpRows.push secondRow

  secondRow.calendar.attr     'placeholder', 'когда обратно'
  secondRow.autocomplete.attr 'placeholder', 'куда'
  
  # add button
  addRowButton = $(".plus p")
  addRowButton.fadeIn(500)
  addRowButton.click ()->
    newRow = new SearchRow() 

    # setting min date 
    previousDate = serpRows.rows[serpRows.rows.length-1].calendar.val()
    
    if previousDate
      previousDate = new Date( new Date(previousDate).getTime() + (1 * 24 * 60 * 60 * 1000) )
      newRow.setMinDate previousDate
    
    serpRows.push newRow

class SearchRow
  constructor: () ->
    # Internals
    @city = null
    @date = null
    @activated = false

    @hotelsCollection = []
    @flightsCollection = []

    @parentElement  = $("#mainContainer")
    @hotelItemHtml  = $('#hotelItem').html()
    @flightItemHtml = $('#flightItem').html()

    # Template
    @html = $($("#searchRowTemplate").html())
    @parentElement.append @html
    @html.hide()
    @html.fadeIn 200

    # Results
    @hotels   = @html.find('.hotels')
    @flights  = @html.find('.flights')

    # Picture 
    @picture  = @html.find("div.image")
    @hello    = @html.find('.splash')

    @cheepFlight        = 0.0
    @bestFlight         = 0.0
    @bestValueFlight    = 0.0
    @averageFlight      = 0.0

    @cheepHotel         = 0.0
    @bestHotel          = 0.0
    @bestValueHotel     = 0.0
    @averageHotel       = 0.0

    # THIS – THAT
    that = @
    
    # Calendar
    @calendar = @html.find(".calendar")
    @calendar.datepicker
      weekStart: 1, 
      dateFormat : "yy-mm-dd"
      minDate: new Date( new Date().getTime() + (2 * 24 * 60 * 60 * 1000) )
      
      beforeShow: (input, inst) ->
        delta = $(window).height() - $(input).offset().top 

        if delta > 205
          marginTop = -48
        else
          marginTop =  48

        cal =  $ "#ui-datepicker-div"
        cal.css 'margin-top', marginTop

        onSelect: (dateText, inst) ->
          that.onSelect
            date: dateText
            type: 'date'

    # Autocomplete
    @autocomplete = @html.find(".geo_autocomplete")
    @autocomplete.autocomplete

      source: (req, res) -> 
        $.ajax
          url: "/api/v1/autocomplete/#{req.term}"
          success: (data) ->

            if not data.value
              return

            res $.map data.value, (item) ->
              label: item.name
              oid: item.oid
              iata: item.iata

      select: (event, item) ->
        that.onSelect
          city: item.item
          type: 'city'

        that.setBackground item.item.label

  showStats: () ->
    stats = @html.find('.stats')

    if not stats.is(":visible")
      stats.hide()
      stats.html($('#stats').html())
      stats.fadeIn(500)

  hind: (data) ->
    @html.find('.stats').hide()

  setMinDate: (date) ->
    @html.find(".calendar").datepicker("option", "minDate", date)

  setMaxDate: (date) ->
    @html.find(".calendar").datepicker("option", "maxDate", date)

  showTeaser: () ->
    @html.find('.stats').parent().prepend($('#teaser').html())

  hindTeaser: () ->
    @html.find('.teaser').fadeOut(200)

  displayHotels: () ->
    @hindTeaser()
    renderCollection = []

    cheepest    = _.min           @hotelsCollection,  (elem) -> elem.price
    cheepest.description = 'самый дешевый'

    bestRating  = _.max           @hotelsCollection,  (elem) -> elem.weightedRating
    bestRating.description = 'лучший рейтинг'

    average     = _.min _.filter(@hotelsCollection,   (elem) -> elem.price <= (cheepest.price + bestRating.price) / 2), (elem) -> elem.weightedRating
    average.description = 'средний'

    bestValue   = _.max _.filter(@hotelsCollection,   (elem) -> elem.price >= average.price),           (elem) ->  elem.weightedRating / elem.price

    bestValue.description = 'цена/качество'

    @cheepHotel     = cheepest.price
    @bestHotel      = bestRating.price
    @bestValueHotel = bestValue.price
    @averageHotel   = average.price

    for hotel in _.sortBy([bestRating, cheepest, average, bestValue], (elem) -> elem.price)

      stars = new Array(hotel.stars).join("★")

      html = @hotelItemHtml
        .replace('%price%', addCommas(Math.ceil(hotel.price)))
        .replace('%name%',  hotel.name)
        .replace('%room%',  hotel.room)
        .replace('%stars%', "#{stars}")
        .replace('%url%',   hotel.url)
        .replace('%description%', hotel.description)

      @hotels.append $(html)

  addHotels: (hotels) ->
    @hotels.parent().parent().addClass('dest-item')
    @hotels.parent().fadeIn(200)
    @hotels.empty()

    for hotel in hotels
      hotel.price = parseFloat(hotel.price)

    @hotelsCollection = @hotelsCollection.concat hotels

    # todo: refactor recalculate rating
    bestRating = _.max(@hotelsCollection, (elem) -> elem.rating).rating
    for hotel in @hotelsCollection
      hotel.weightedRating = hotel.rating / bestRating

    @displayHotels()

  displayFlights: () ->
    @hindTeaser()
    renderCollection = []

    cheepest    = _.min         @flightsCollection,  (elem) -> elem.price
    cheepest.description    = 'самый дешевый'

    fastest     = _.max         @flightsCollection,  (elem) -> elem.rating
    fastest.description     = 'самый быстрый'

    bestValue   = _.max _.filter(@flightsCollection,  (elem) -> elem.price <= 1.2 * (cheepest.price + fastest.price) / 2), (elem) -> elem.rating
    bestValue.description   = 'цена/качество'

    average     = _.min _.filter(@flightsCollection, (elem) -> elem != cheepest),   (elem) -> elem.price
    average.description     = 'средний'

    @cheepFlight        = cheepest.price
    @bestFlight         = fastest.price
    @bestValueFlight    = bestValue.price
    @averageFlight      = average.price

    flights = _.uniq([fastest, cheepest, bestValue, average])
    if flights.length is 1
      flights[0].description = 'единственный'

    for flight in _.sortBy(flights, (elem) -> elem.price)

      pluralHours     = pluralize(flight.timeSpan, "часов", "час", "часа")
      timespanString  = "#{flight.timeSpan} #{pluralHours}"

      if flight.transferNumber != 0
        pluralTransfers = pluralize(flight.transferNumber, "пересадок", "пересадка", "пересадки")
        transferString  = "#{flight.transferNumber} #{pluralTransfers}"
      else
        transferString  = "Прямой рейс"

      html = @flightItemHtml
        .replace('%price%',           addCommas flight.price)
        .replace('%arrival%',         flight.arrival)
        .replace('%departure%',       flight.departure)
        .replace('%timeSpan%',        timespanString)
        .replace('%transferNumber%',  transferString)
        .replace('%url%',             flight.url)
        .replace('%description%',     flight.description)

      @flights.append $(html)

  addFlights: (flights) ->   
    @flights.parent().parent().addClass('dest-item')
    @flights.parent().fadeIn(200)
    @flights.empty()
    @flightsCollection = @flightsCollection.concat flights

    minSpan = _.min(@flightsCollection, (elem) -> elem.timeSpan).timeSpan

    for flight in @flightsCollection
      flight.rating = minSpan / flight.timeSpan

    @displayFlights()

  setBackground: (term) ->
     that = @
     $.ajax
      url: "/api/v1/image/#{term}"
      success: (data) ->
        if data.status is "ok"      
          that.picture.css('background', "url('#{data.value.image}') no-repeat center #000")
          that.html.find("input.calendar")        .css('background-color', '#000')
          that.html.find("input.geo_autocomplete").css('background-color', '#000')

  showHotelsLoading:  () ->
    @hotels.html  $('#loading').html()
  
  showFlightsLoading: () ->
    @flights.html $('#loading').html()

  onSelect: (data) ->
    if data.city
      @city = data.city

    if data.date
      @date = data.date

    if not @city or not @date
      return

    @activated = true

    @hotelsCollection = []
    @flightsCollection = []

    if @rowCollectionCallback
      @rowCollectionCallback data

class SearchRowCollection
  constructor: ->
    @rows = []
    @numAdults = 2
    @currentSignature = ''

    that = @

    $("#numAdults").change () ->
      that.numAdults = parseInt($("#numAdults").val())
      that.refreshSearch()

  push: (row) ->
    rowNumber = @rows.length
    @rows.push row
    row.rowCollectionCallback = (data) => 
      @onRowSelection rowNumber, data

  calculateStatistics: () ->
    cheep     = 0.0
    average   = 0.0
    bestValue = 0.0
    best      = 0.0

    for row in @rows
      cheep     += (row.cheepHotel      + row.cheepFlight)
      average   += (row.averageHotel    + row.averageFlight)
      bestValue += (row.bestValueHotel  + row.bestValueFlight)
      best      += (row.bestHotel       + row.bestFlight)

    @rows[0].html.find('.inner-stats span.cheep'    ).html(addCommas(Math.ceil(cheep)))
    @rows[0].html.find('.inner-stats span.average'  ).html(addCommas(Math.ceil(average)))
    @rows[0].html.find('.inner-stats span.bestValue').html(addCommas(Math.ceil(bestValue)))
    @rows[0].html.find('.inner-stats span.best'     ).html(addCommas(Math.ceil(best)))

  makeSignature: () ->
    signature = "#{@numAdults}"

    for row in @dataRows
      signature += "#{row.origin.iata}:#{row.origin.date}-#{row.destination.iata}:#{row.destination.date}"

    return signature

  startSearch: () ->
    if @dataRows.length > 0
        @currentSignature = @makeSignature()
        serp.startSearch @dataRows, { adults: @numAdults }, @currentSignature 

  refreshSearch: () ->
    for row in @rows
      row.showHotelsLoading()
      row.showFlightsLoading()

      row.hotelsCollection  = []
      row.flightsCollection = []

    @startSearch()

  onRowSelection: (rowNumber, row) ->    
    if @rows.length < 2
      return

    if rowNumber != (@rows.length - 1)
      nextDate    = new Date( new Date(row.date).getTime() + (1 * 24 * 60 * 60 * 1000) )
      @rows[rowNumber + 1].setMinDate nextDate

    if rowNumber != 0
      previosDate = new Date( new Date(row.date).getTime() - (1 * 24 * 60 * 60 * 1000) )
      @rows[rowNumber - 1].setMaxDate previosDate

    @dataRows = []
    for i in [0..@rows.length-2] when @rows[i].activated and @rows[i+1].activated

      @dataRows.push
        origin:
          iata: @rows[i  ].city.iata
          oid:  @rows[i  ].city.oid
          date: @rows[i  ].date
        destination:
          iata: @rows[i+1].city.iata
          oid:  @rows[i+1].city.oid
          date: @rows[i+1].date

    if rowNumber >= 1
      @rows[rowNumber-1].showHotelsLoading()
      @rows[rowNumber-1].flightsCollection = []

      if row.type is 'city'
        @rows[rowNumber-1].hotelsCollection = []
        @rows[rowNumber-1].showFlightsLoading()

    @rows[rowNumber].showFlightsLoading()
    @rows[rowNumber].showHotelsLoading()

    @startSearch()


class SocketSERP
  constructor: (funcs) ->
    @socket = io.connect 'http://localhost/'
    #@socket = io.connect 'http://78.46.187.179/'
    
    @socket.on 'hotels ready', (data) ->
      funcs.onHotelsReady data

    @socket.on 'flights ready', (data) ->
      funcs.onFlightsReady data

  startSearch: (rows, extra, signature) ->
    @socket.emit 'start search'
      rows: rows
      extra: extra
      signature: signature

# helpers
pluralize = (number, a, b, c) ->
  if number >= 10 and number <= 20
    return a

  if number == 1 or number % 10 == 1
    return b

  if number <= 4 or number % 10 == 4
    return c

  return a

delay = (ms, func) -> 
  setTimeout func, ms

addCommas = (nStr) ->
  nStr += ''
  x = nStr.split('.')
  x1 = x[0]
  if x.length > 1
    x2 = ('.' + x[1])
  else
    x2 = ''
  rgx = /(\d+)(\d{3})/
  while (rgx.test(x1)) 
    x1 = x1.replace(rgx, '$1' + ' ' + '$2')
  return (x1 + x2)

jQuery(document).ready ->
  main()