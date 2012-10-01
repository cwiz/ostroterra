dateFormat  = require "dateformat"
moment      = require "moment"
Mongolian   = require "mongolian"
request     = require "request"
Sync        = require "sync"
url         = require "url"
xml2js      = require "xml2js"

# Database stuff
server        = new Mongolian
db            = server.db "ostroterra"

airports      = db.collection "airports"
suggest       = db.collection "suggest"

suggest.ensureIndex { query: 1}
airports.ensureIndex { query: 1}

# Globals
moment.lang('ru')


queryOstrovokAutocomplete = (query, cb) ->
  ostUrl = "http://ostrovok.ru/api/site/multicomplete.json?query=#{query}&regions_ver=v5"
  
  request ostUrl, (error, response, body) ->

    console.log ">>> queried ostrovok autocomplete | #{ostUrl} | status #{response.statusCode}"
    
    if not error and response.statusCode is 200
      json = JSON.parse(response.body)
      final_json = []

      for obj in json.regions when (obj.target is "search" and obj.type is 'city')
        country = obj.country
        name    = obj.name
        id      = obj.id

        if country isnt "Россия"
          name += ", #{country}"

        final_json.push
          name:     name
          oid:      id
          country:  country
      
      cb final_json


queryEviterraAutocomplete = (query, cb) ->
  eviterraUrl = "https://eviterra.com/complete.json?val=#{query}"

  request eviterraUrl, (error, response, body) ->

    console.log ">>> queried eviterra autocomplete | #{eviterraUrl} | status #{response.statusCode}"
    
    if not error and response.statusCode is 200
      json = JSON.parse(response.body)
      final_json = []

      for item in json.data when item.type is "city"

        name    = item.name
        country = item.area
        iata    = item.iata

        if country isnt "Россия"
          name += ", #{country}"

        final_json.push
          name:     name
          iata:     iata
          country:  country

      cb final_json


glueAutocompleteResults = (ostrovokResults, eviterraResults, cb) ->
  if ostrovokResults is null or eviterraResults is null
    return

  final_results = []

  pushResults = (ostrovok, eviterra) ->

    final_results.push 
      oid:  ostrovok.oid
      iata: eviterra.iata
      name: eviterra.name

  for o in ostrovokResults
    for e in eviterraResults

      if o.name == e.name and o.country == e.country
        pushResults(o, e)

      else
        osn = o.name.split(',')
        evn = e.name.split(',')

        if osn[0] == evn[0] and o.country == e.country
          pushResults(o, e)
        
  cb final_results


queryEviterraSerp = (args, cb) ->
  evUrl = "http://api.eviterra.com/avia/v1/variants.xml?from=#{args.departure}&to=#{args.destination}&date1=#{args.arrival}&adults=#{args.adults}"

  request evUrl, (error, response, body) ->
    console.log ">>> queried eviterra serp | #{evUrl} | status #{response.statusCode}"
    
    if error or response.statusCode is not 200
      return

    parser = new xml2js.Parser()

    parser.parseString response.body, (err, json) ->
      if err
        return

      cb json

queryOstrovokSerp = (args, cb) ->
  ostUrl = "http://ostrovok.ru/api/v1/search/page/#{args.page}/?region_id=#{args.region_id}&arrivalDate=#{args.arrival}&departureDate=#{args.departure}&room1_numberOfAdults=#{args.adults}"
  
  request ostUrl, (error, response, body) ->
    console.log ">>> queried ostrovok serp | #{ostUrl} | status #{response.statusCode}"
    if not error and response.statusCode is 200
      json = JSON.parse(response.body)
      page = json._next_page

      cb json
      if page
        args.page = page
        queryOstrovokSerp args, cb

exports.autocomplete = (req, res) ->
  query = req.params.query

  if not query
    res.send
      status: "error"
      message: "please supply q GET param"

  autocompleteCallback = (results, insert) ->

    if insert
      suggest.insert 
        query:    query
        results:  results

    res.send
      status: "ok"
      value: results

  suggest.findOne { query: query }, (err, results) ->

    console.log "searched mongodb for #{query}: results: #{results}"
    
    if results
      autocompleteCallback results.results, false
      return

    ostrovokResults = null
    eviterraResults = null

    postQueryCallback = (results) -> autocompleteCallback results, true

    queryOstrovokAutocomplete query, (result) ->
      ostrovokResults = result
      glueAutocompleteResults(ostrovokResults, eviterraResults, postQueryCallback)

    queryEviterraAutocomplete query, (result) ->
      eviterraResults = result
      glueAutocompleteResults(ostrovokResults, eviterraResults, postQueryCallback)

exports.search = (socket) ->

  socket.on 'start search', (data) ->

    rowNumber = 0
    departure = null
    destination = null

    data.rows.push 

      destination:
        oid: null
        iata: data.rows[ 0  ].origin.iata
        date: data.rows[-1..][0].destination.date
      
      origin:
        oid: null
        iata: data.rows[-1..][0].destination.iata
        date: data.rows[-1..][0].destination.date

    for row in data.rows
      
      # destintation id for ostrovok
      destinationOid  = row.destination.oid
      
      # departure/destination airport codes for eviterra
      destiantionIata = row.destination.iata
      departureIata   = row.origin.iata
      
      # arrival/departure dates
      arrivalDate     = row.origin.date
      departureDate   = row.destination.date

      adults = data.extra.adults
      page = 1

      combineSerps = (destinationOid, arrivalDate, departureDate, adults, page, departureIata, destiantionIata, rowNumber) ->
        
        processOstrovokResponse = (json) ->

          hotels = json.hotels
          rates  = json._meta.rates

          new_hotels = []
          
          for hotel in hotels when hotel.rooms

            rating = 0
            if hotel.rating?.total?
              count  = hotel.rating.count
              
              if count > 25
                rating = hotel.rating.total * count

            price = hotel.rooms[0].total_rate * rates[hotel.rooms[0].currency]
            stars = 1

            if hotel.star_rating
              stars = Math.ceil(hotel.star_rating/10.0) + 1
            
            if price
              new_hotels.push 
                name:   hotel.name
                stars:  stars
                price:  price
                rating: rating
                url:    'http://ostrovok.ru' + hotel.url + "&utm_source=ostroterra"

          socket.emit 'hotels ready'
            hotels:     new_hotels
            rowNumber:  rowNumber
            signature:  data.signature

        processEviterraResponse = (flights) ->

          if not flights or not flights.variant
            return

          # used to get timezone out of mongoDb
          getAirportDetails = (iata, callback) ->
            airports.findOne { iata: iata }, (err, airport) ->
              callback null, airport
              
          syncMassageFlights = () ->

              new_flights = []

              for variant in flights.variant

                if variant.segment.flight.length?
                  transferNumber  = variant.segment.flight.length
                  firstFlight     = variant.segment.flight[0]
                  lastFlight      = variant.segment.flight[transferNumber-1]
                else
                  transferNumber  = 1
                  firstFlight     = variant.segment.flight
                  lastFlight      = firstFlight               

                arrivalDestinationDate  = moment lastFlight.arrivalDate + 'T' + lastFlight.arrivalTime
                arrivalAirport          = getAirportDetails.sync null, lastFlight.arrival
                
                departureOriginDate     = moment firstFlight.departureDate + 'T' + firstFlight.departureTime
                departureAirport        = getAirportDetails.sync null, firstFlight.departure

                # UTC massage
                utcArrivalDate    = arrivalDestinationDate.clone().subtract('hours', arrivalAirport.timezone  )
                utcDepartureDate  = departureOriginDate.clone().subtract('hours', departureAirport.timezone)

                flightTimeSpan   = utcArrivalDate.diff   utcDepartureDate, 'hours'
                  
                new_flights.push
                  arrival:        arrivalDestinationDate.format('LL')
                  departure:      departureOriginDate.format('LL')
                  price:          parseInt(variant.price)
                  timeSpan:       flightTimeSpan
                  transferNumber: transferNumber - 1
                  url:            variant.url + "ostroterra"

              return new_flights

          Sync syncMassageFlights, (err, new_flights) ->

            if err
              console.log "error #{err}"
              return

            socket.emit 'flights ready'
              flights:   new_flights
              rowNumber: rowNumber
              signature: data.signature

        args = 
          region_id:    destinationOid
          arrival:      arrivalDate
          departure:    departureDate
          adults:       adults
          page:         page    
        queryOstrovokSerp args, processOstrovokResponse
          
        args = 
          departure:    departureIata
          destination:  destiantionIata
          arrival:      arrivalDate
          adults:       adults
          children:     0
          infants:      0
        queryEviterraSerp args, processEviterraResponse

      combineSerps destinationOid, arrivalDate, departureDate, adults, page, departureIata, destiantionIata, rowNumber
      rowNumber++

exports.image = (req, res) ->
  query = encodeURIComponent(req.params.query)

  flickrKey = "7925109a48c26fe53555687f9d46a076"
  flickrSecret = "c936db59c720b4d5"
  photoUrl = null
  coordinates = null

  flickrUrl = "http://api.flickr.com/services/rest/?per_page=10&sort=relevance&format=json&content_type=1&nojsoncallback=1&method=flickr.photos.search&api_key=#{flickrKey}&text=#{query}"
  request flickrUrl, (error, response, body) ->
    console.log ">>> queried flickr search | #{flickrUrl} | status #{response.statusCode}"
    if not error and response.statusCode is 200
      json = JSON.parse(response.body)
      len = json.photos.photo.length
      randomIndex = Math.floor((Math.random()*len));
      photo = json.photos.photo[randomIndex]
      if photo
        photoUrl = "http://farm#{photo.farm}.staticflickr.com/#{photo.server}/#{photo.id}_#{photo.secret}_z.jpg"
        sendResult()

  googleUrl = "http://maps.googleapis.com/maps/api/geocode/json?address=#{query}&sensor=true"
  request googleUrl, (error, response, body) ->
    console.log ">>> queried google geocode | #{googleUrl} | status #{response.statusCode}"
    if not error and response.statusCode is 200
      json = JSON.parse(response.body)
      result = json.results[0]
      if result
        coordinates = result.geometry.location
        sendResult()

  sendResult = ->
    if photoUrl and coordinates
      res.json
        status: 'ok'
        value: 
          image: photoUrl
          coordinates: coordinates