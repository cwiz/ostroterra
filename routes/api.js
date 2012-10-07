(function() {
  var Mongolian, Sync, airports, dateFormat, db, glueAutocompleteResults, moment, queryEviterraAutocomplete, queryEviterraSerp, queryOstrovokAutocomplete, queryOstrovokSerp, request, server, suggest, url, xml2js;
  dateFormat = require("dateformat");
  moment = require("moment");
  Mongolian = require("mongolian");
  request = require("request");
  Sync = require("sync");
  url = require("url");
  xml2js = require("xml2js");
  server = new Mongolian;
  db = server.db("ostroterra");
  airports = db.collection("airports");
  suggest = db.collection("suggest");
  suggest.ensureIndex({
    query: 1
  });
  airports.ensureIndex({
    query: 1
  });
  moment.lang('ru');
  queryOstrovokAutocomplete = function(query, cb) {
    var ostUrl;
    ostUrl = "http://ostrovok.ru/api/site/multicomplete.json?query=" + query + "&regions_ver=v5";
    return request(ostUrl, function(error, response, body) {
      var country, final_json, id, json, name, obj, _i, _len, _ref;
      console.log(">>> queried ostrovok autocomplete | " + ostUrl + " | status " + response.statusCode);
      if (!error && response.statusCode === 200) {
        json = JSON.parse(response.body);
        final_json = [];
        _ref = json.regions;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          obj = _ref[_i];
          if (obj.target === "search" && obj.type === 'city') {
            country = obj.country;
            name = obj.name;
            id = obj.id;
            if (country !== "Россия") {
              name += ", " + country;
            }
            final_json.push({
              name: name,
              oid: id,
              country: country
            });
          }
        }
        return cb(final_json);
      }
    });
  };
  queryEviterraAutocomplete = function(query, cb) {
    var eviterraUrl;
    eviterraUrl = "https://eviterra.com/complete.json?val=" + query;
    return request(eviterraUrl, function(error, response, body) {
      var country, final_json, iata, item, json, name, _i, _len, _ref;
      console.log(">>> queried eviterra autocomplete | " + eviterraUrl + " | status " + response.statusCode);
      if (!error && response.statusCode === 200) {
        json = JSON.parse(response.body);
        final_json = [];
        _ref = json.data;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          item = _ref[_i];
          if (item.type === "city") {
            name = item.name;
            country = item.area;
            iata = item.iata;
            if (country !== "Россия") {
              name += ", " + country;
            }
            final_json.push({
              name: name,
              iata: iata,
              country: country
            });
          }
        }
        return cb(final_json);
      }
    });
  };
  glueAutocompleteResults = function(ostrovokResults, eviterraResults, cb) {
    var e, evn, final_results, o, osn, pushResults, _i, _j, _len, _len2;
    if (ostrovokResults === null || eviterraResults === null) {
      return;
    }
    final_results = [];
    pushResults = function(ostrovok, eviterra) {
      return final_results.push({
        oid: ostrovok.oid,
        iata: eviterra.iata,
        name: eviterra.name
      });
    };
    for (_i = 0, _len = ostrovokResults.length; _i < _len; _i++) {
      o = ostrovokResults[_i];
      for (_j = 0, _len2 = eviterraResults.length; _j < _len2; _j++) {
        e = eviterraResults[_j];
        if (o.name === e.name && o.country === e.country) {
          pushResults(o, e);
        } else {
          osn = o.name.split(',');
          evn = e.name.split(',');
          if (osn[0] === evn[0] && o.country === e.country) {
            pushResults(o, e);
          }
        }
      }
    }
    return cb(final_results);
  };
  queryEviterraSerp = function(args, cb) {
    var evUrl;
    evUrl = "http://api.eviterra.com/avia/v1/variants.xml?from=" + args.departure + "&to=" + args.destination + "&date1=" + args.arrival + "&adults=" + args.adults;
    return request(evUrl, function(error, response, body) {
      var parser;
      console.log(">>> queried eviterra serp | " + evUrl + " | status " + response.statusCode);
      if (error || response.statusCode === !200) {
        return;
      }
      parser = new xml2js.Parser();
      return parser.parseString(response.body, function(err, json) {
        if (err) {
          return;
        }
        return cb(json);
      });
    });
  };
  queryOstrovokSerp = function(args, cb) {
    var ostUrl;
    ostUrl = "http://ostrovok.ru/api/v1/search/page/" + args.page + "/?region_id=" + args.region_id + "&arrivalDate=" + args.arrival + "&departureDate=" + args.departure + "&room1_numberOfAdults=" + args.adults;
    return request(ostUrl, function(error, response, body) {
      var json, page;
      console.log(">>> queried ostrovok serp | " + ostUrl + " | status " + response.statusCode);
      if (!error && response.statusCode === 200) {
        json = JSON.parse(response.body);
        page = json._next_page;
        cb(json);
        if (page) {
          args.page = page;
          return queryOstrovokSerp(args, cb);
        }
      }
    });
  };
  exports.autocomplete = function(req, res) {
    var autocompleteCallback, query;
    query = req.params.query;
    if (!query) {
      res.send({
        status: "error",
        message: "please supply q GET param"
      });
    }
    autocompleteCallback = function(results, insert) {
      if (insert) {
        suggest.insert({
          query: query,
          results: results
        });
      }
      return res.send({
        status: "ok",
        value: results
      });
    };
    return suggest.findOne({
      query: query
    }, function(err, results) {
      var eviterraResults, ostrovokResults, postQueryCallback;
      console.log("searched mongodb for " + query + ": results: " + results);
      if (results) {
        autocompleteCallback(results.results, false);
        return;
      }
      ostrovokResults = null;
      eviterraResults = null;
      postQueryCallback = function(results) {
        return autocompleteCallback(results, true);
      };
      queryOstrovokAutocomplete(query, function(result) {
        ostrovokResults = result;
        return glueAutocompleteResults(ostrovokResults, eviterraResults, postQueryCallback);
      });
      return queryEviterraAutocomplete(query, function(result) {
        eviterraResults = result;
        return glueAutocompleteResults(ostrovokResults, eviterraResults, postQueryCallback);
      });
    });
  };
  exports.search = function(socket) {
    return socket.on('start search', function(data) {
      var adults, arrivalDate, combineSerps, departure, departureDate, departureIata, destiantionIata, destination, destinationOid, page, row, rowNumber, _i, _len, _ref, _results;
      rowNumber = 0;
      departure = null;
      destination = null;
      data.rows.push({
        destination: {
          oid: null,
          iata: data.rows[0].origin.iata,
          date: data.rows.slice(-1)[0].destination.date
        },
        origin: {
          oid: null,
          iata: data.rows.slice(-1)[0].destination.iata,
          date: data.rows.slice(-1)[0].destination.date
        }
      });
      _ref = data.rows;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        row = _ref[_i];
        destinationOid = row.destination.oid;
        destiantionIata = row.destination.iata;
        departureIata = row.origin.iata;
        arrivalDate = row.origin.date;
        departureDate = row.destination.date;
        adults = data.extra.adults;
        page = 1;
        combineSerps = function(destinationOid, arrivalDate, departureDate, adults, page, departureIata, destiantionIata, rowNumber) {
          var args, processEviterraResponse, processOstrovokResponse;
          processOstrovokResponse = function(json) {
            var count, hotel, hotels, new_hotels, price, rates, rating, stars, _j, _len2, _ref2;
            hotels = json.hotels;
            rates = json._meta.rates;
            new_hotels = [];
            for (_j = 0, _len2 = hotels.length; _j < _len2; _j++) {
              hotel = hotels[_j];
              if (hotel.rooms) {
                rating = 0;
                if (((_ref2 = hotel.rating) != null ? _ref2.total : void 0) != null) {
                  count = hotel.rating.count;
                  if (count > 25) {
                    rating = hotel.rating.total * count;
                  }
                }
                price = hotel.rooms[0].total_rate * rates[hotel.rooms[0].currency];
                stars = 1;
                if (hotel.star_rating) {
                  stars = Math.ceil(hotel.star_rating / 10.0) + 1;
                }
                if (price) {
                  new_hotels.push({
                    name: hotel.name,
                    stars: stars,
                    price: price,
                    rating: rating,
                    url: 'http://ostrovok.ru' + hotel.url + "&partner_slug=ostroterra"
                  });
                }
              }
            }
            return socket.emit('hotels ready', {
              hotels: new_hotels,
              rowNumber: rowNumber,
              signature: data.signature
            });
          };
          processEviterraResponse = function(flights) {
            var getAirportDetails, syncMassageFlights;
            if (!flights || !flights.variant) {
              return;
            }
            getAirportDetails = function(iata, callback) {
              return airports.findOne({
                iata: iata
              }, function(err, airport) {
                return callback(null, airport);
              });
            };
            syncMassageFlights = function() {
              var arrivalAirport, arrivalDestinationDate, departureAirport, departureOriginDate, firstFlight, flightTimeSpan, lastFlight, new_flights, transferNumber, utcArrivalDate, utcDepartureDate, variant, _j, _len2, _ref2;
              new_flights = [];
              _ref2 = flights.variant;
              for (_j = 0, _len2 = _ref2.length; _j < _len2; _j++) {
                variant = _ref2[_j];
                if (variant.segment.flight.length != null) {
                  transferNumber = variant.segment.flight.length;
                  firstFlight = variant.segment.flight[0];
                  lastFlight = variant.segment.flight[transferNumber - 1];
                } else {
                  transferNumber = 1;
                  firstFlight = variant.segment.flight;
                  lastFlight = firstFlight;
                }
                arrivalDestinationDate = moment(lastFlight.arrivalDate + 'T' + lastFlight.arrivalTime);
                arrivalAirport = getAirportDetails.sync(null, lastFlight.arrival);
                departureOriginDate = moment(firstFlight.departureDate + 'T' + firstFlight.departureTime);
                departureAirport = getAirportDetails.sync(null, firstFlight.departure);
                utcArrivalDate = arrivalDestinationDate.clone().subtract('hours', arrivalAirport.timezone);
                utcDepartureDate = departureOriginDate.clone().subtract('hours', departureAirport.timezone);
                flightTimeSpan = utcArrivalDate.diff(utcDepartureDate, 'hours');
                if (flightTimeSpan === 0) {
                  flightTimeSpan = 1;
                }
                new_flights.push({
                  arrival: arrivalDestinationDate.format('LL'),
                  departure: departureOriginDate.format('LL'),
                  price: parseInt(variant.price),
                  timeSpan: flightTimeSpan,
                  transferNumber: transferNumber - 1,
                  url: variant.url + "ostroterra"
                });
              }
              return new_flights;
            };
            return Sync(syncMassageFlights, function(err, new_flights) {
              if (err) {
                console.log("error " + err);
                return;
              }
              return socket.emit('flights ready', {
                flights: new_flights,
                rowNumber: rowNumber,
                signature: data.signature
              });
            });
          };
          args = {
            region_id: destinationOid,
            arrival: arrivalDate,
            departure: departureDate,
            adults: adults,
            page: page
          };
          queryOstrovokSerp(args, processOstrovokResponse);
          args = {
            departure: departureIata,
            destination: destiantionIata,
            arrival: arrivalDate,
            adults: adults,
            children: 0,
            infants: 0
          };
          return queryEviterraSerp(args, processEviterraResponse);
        };
        combineSerps(destinationOid, arrivalDate, departureDate, adults, page, departureIata, destiantionIata, rowNumber);
        _results.push(rowNumber++);
      }
      return _results;
    });
  };
  exports.image = function(req, res) {
    var coordinates, flickrKey, flickrSecret, flickrUrl, googleUrl, photoUrl, query, sendResult;
    query = encodeURIComponent(req.params.query);
    flickrKey = "7925109a48c26fe53555687f9d46a076";
    flickrSecret = "c936db59c720b4d5";
    photoUrl = null;
    coordinates = null;
    flickrUrl = "http://api.flickr.com/services/rest/?per_page=10&sort=relevance&format=json&content_type=1&nojsoncallback=1&method=flickr.photos.search&api_key=" + flickrKey + "&text=" + query;
    request(flickrUrl, function(error, response, body) {
      var json, len, photo, randomIndex;
      console.log(">>> queried flickr search | " + flickrUrl + " | status " + response.statusCode);
      if (!error && response.statusCode === 200) {
        json = JSON.parse(response.body);
        len = json.photos.photo.length;
        randomIndex = Math.floor(Math.random() * len);
        photo = json.photos.photo[randomIndex];
        if (photo) {
          photoUrl = "http://farm" + photo.farm + ".staticflickr.com/" + photo.server + "/" + photo.id + "_" + photo.secret + "_z.jpg";
          return sendResult();
        }
      }
    });
    googleUrl = "http://maps.googleapis.com/maps/api/geocode/json?address=" + query + "&sensor=true";
    request(googleUrl, function(error, response, body) {
      var json, result;
      console.log(">>> queried google geocode | " + googleUrl + " | status " + response.statusCode);
      if (!error && response.statusCode === 200) {
        json = JSON.parse(response.body);
        result = json.results[0];
        if (result) {
          coordinates = result.geometry.location;
          return sendResult();
        }
      }
    });
    return sendResult = function() {
      if (photoUrl && coordinates) {
        return res.json({
          status: 'ok',
          value: {
            image: photoUrl,
            coordinates: coordinates
          }
        });
      }
    };
  };
}).call(this);
