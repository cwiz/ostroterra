api 	= require "./api.js"
static 	= require "./static.js"

exports.index = (req, res) ->
  res.render "index",
    title: "Index Page"

exports.autocomplete 	= api.autocomplete
exports.search        	= api.search
exports.image 		  	= api.image
exports.about 			= static.about