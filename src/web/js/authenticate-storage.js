// Defines storageAPI (as a promise) for others to use
var storageAPIDeferred = Q.defer();
var storageAPI = storageAPIDeferred.promise;
function handleClientLoad(clientId, apiKey) {
  //console.log('config.google.clientId = ' + config.google.clientId);
  //clientId = config.google.clientId;
  //try to get clientId from config.google
  console.log('doing handleClientLoad ' + clientId + ', ' + apiKey);
  var api = createProgramCollectionAPI(clientId, apiKey, "code.pyret.org", true);
  console.log('auth/api = ' + JSON.stringify(api));

  console.log('typeof api = ' + (typeof api));

  api.then(function(api) {
    console.log('api successfully created = ' + JSON.stringify(api));
    storageAPIDeferred.resolve(api);
  });
  api.fail(function(err) {
    storageAPIDeferred.reject(err);
    console.log("Not logged in; proceeding without login info", err);
  });
  /*
  define("gdrive-credentials", [], function() {
    var thisApiKey = apiKey;
    return {
      getCredentials: function() {
        return {
          apiKey: thisApiKey
        };
      },
      setCredentials: function(apiKey) {
        thisApiKey = apiKey;
      }
    };
  });
  */
}
