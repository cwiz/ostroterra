(function(){
  var api, search, staticPages;
  api = require("./api.js");
  search = require("./search.js");
  staticPages = require("./static.js");
  exports.index = function(req, res){
    return res.render("index", {
      title: "Index Page"
    });
  };
  exports.autocomplete = api.autocomplete;
  exports.search = search.search;
  exports.image = api.image;
  exports.about = staticPages.about;
}).call(this);
