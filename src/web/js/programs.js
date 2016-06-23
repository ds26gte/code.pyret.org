// assumes gapi bound to Google API

function createProgramCollectionAPI(clientId, apiKey, collectionName, immediate) {
  console.log('doing createProgramCollectionAPI clientId= ' + clientId + ' immediate= ' + immediate);

  //gapi.client.setApiKey(apiKey);
  var drive;
  var SCOPE = "https://www.googleapis.com/auth/drive.file "
    + "https://www.googleapis.com/auth/drive.install";
  /*
  var SCOPE = "https://www.googleapis.com/auth/drive.file "
    + "https://www.googleapis.com/auth/drive "
    + "https://spreadsheets.google.com/feeds "
    + "https://www.googleapis.com/auth/drive.install";
  */
  var FOLDER_MIME = "application/vnd.google-apps.folder";
  var BACKREF_KEY = "originalProgram";
  var PUBLIC_LINK = "pubLink";

  var refresh = function(immediate) {
    return reauth(true);
  };

  function authCheck(f) {
    function isAuthFailure(result) {
      return result &&
        (result.error && result.error.code && result.error.code === 401) ||
        (result.code && result.code === 401);
    }
    var retry = f().then(function(result) {
      if(isAuthFailure(result)) {
        return refresh().then(function(authResult) {
          if(!authResult || authResult.error) {
            return {error: { code: 401, message: "Couldn't re-authorize" }};
          }
          else {
            return f();
          }
        });
      } else {
        return result;
      }
    });
    return retry.then(function(result) {
      if(isAuthFailure(result)) {
        throw new Error("Authentication failure");
      }
      return result;
    });
  }

  function gQ(request, skipAuth) {
    if (skipAuth) {
      console.log('gQ skipping auth');
    }
    var oldAccess = gapi.auth.getToken();
    if(skipAuth) { gapi.auth.setToken({access_token: null}); }
    var ret = failCheck(authCheck(function() {
      var d = Q.defer();
      request.execute(function(result) {
        d.resolve(result);
      });
      return d.promise;
    }));
    if(skipAuth) {
      ret.fin(function() {
        gapi.auth.setToken({access_token: oldAccess});
      });
    }
    return ret;
  }

  function DriveError(err) {
    this.err = err;
  }
  DriveError.prototype = Error.prototype;

  function failCheck(p) {
    return p.then(function(result) {
      // Network error
      if(result && result.error) {
        console.error("Error fetching file from gdrive: ", result);
        throw new DriveError(result);
      }
      if(result && (typeof result.code === "number") && (result.code >= 400)) {
        console.error("40X Error fetching file from gdrive: ", result);
        throw new DriveError(result);
      }
      return result;
    });
  }

  function createAPI(baseCollection) {
    function makeSharedFile(googFileObject) {
      return {
        shared: true,
        getContents: function() {
          var proxyDownloadLink = "/downloadGoogleFile?" + googFileObject.id;
          return Q($.ajax(proxyDownloadLink, {
            method: "get",
            dataType: 'text'
          })).then(function(response) {
            return response;
          });
        },
        getName: function() {
          return googFileObject.title;
        },
        getDownloadLink: function() {
          return googFileObject.downloadUrl;
        },
        getModifiedTime: function() {
          return googFileObject.modifiedDate;
        },
        getUniqueId: function() {
          return googFileObject.id;
        },
      };

    }
    function makeFile(googFileObject, mimeType, fileExtension) {
      return {
        shared: false,
        getName: function() {
          return googFileObject.title;
        },
        getDownloadLink: function() {
          return googFileObject.downloadUrl;
        },
        getModifiedTime: function() {
          return googFileObject.modifiedDate;
        },
        getUniqueId: function() {
          return googFileObject.id;
        },
        getExternalURL: function() {
          return googFileObject.alternateLink;
        },
        getShares: function() {
          return gQ(drive.files.list({
              q: "trashed=false and properties has {key='" + BACKREF_KEY + "' and value='" + googFileObject.id + "' and visibility='PRIVATE'}"
            }))
          .then(function(files) {
            if(!files.items) { return []; }
            else { return files.items.map(fileBuilder); }
          });;
        },
        getContents: function() {
          return Q($.ajax(googFileObject.downloadUrl, {
            method: "get",
            dataType: 'text',
            headers: {'Authorization': 'Bearer ' + gapi.auth.getToken().access_token },
          })).then(function(response) {
            return response;
          });
        },
        rename: function(newName) {
          return gQ(drive.files.update({
            fileId: googFileObject.id,
            resource: {
              'title': newName
            }
          })).then(fileBuilder);
        },
        makeShareCopy: function() {
          var shareCollection = findOrCreateShareDirectory();
          var newFile = shareCollection.then(function(c) {
            var sharedTitle = googFileObject.title;
            return gQ(drive.files.copy({
              fileId: googFileObject.id,
              resource: {
                "parents": [{id: c.id}],
                "title": sharedTitle,
                "properties": [{
                    "key": BACKREF_KEY,
                    "value": String(googFileObject.id),
                    "visibility": "PRIVATE"
                  }]
              }
            }));
          });
          var updated = newFile.then(function(newFile) {
            return gQ(drive.permissions.insert({
              fileId: newFile.id,
              resource: {
                'role': 'reader',
                'type': 'anyone',
                'id': googFileObject.permissionId
              }
            }));
          });
          return Q.all([newFile, updated]).spread(function(fileObj) {
            return fileBuilder(fileObj);
          });
        },
        save: function(contents, newRevision) {
          // NOTE(joe): newRevision: false will cause badRequest errors as of
          // April 30, 2014
          if(newRevision) {
            var params = { 'newRevision': true };
          }
          else {
            var params = {};
          }
          const boundary = '-------314159265358979323846';
          const delimiter = "\r\n--" + boundary + "\r\n";
          const close_delim = "\r\n--" + boundary + "--";
          var metadata = {
            'mimeType': mimeType,
            'fileExtension': fileExtension
          };
          var multipartRequestBody =
                delimiter +
                'Content-Type: application/json\r\n\r\n' +
                JSON.stringify(metadata) +
                delimiter +
                'Content-Type: text/plain\r\n' +
                '\r\n' +
                contents +
                close_delim;

          var request = gapi.client.request({
              'path': '/upload/drive/v2/files/' + googFileObject.id,
              'method': 'PUT',
              'params': {'uploadType': 'multipart'},
              'headers': {
                'Content-Type': 'multipart/mixed; boundary="' + boundary + '"'
              },
              'body': multipartRequestBody});
          return gQ(request).then(fileBuilder);
        },
        _googObj: googFileObject
      };
    }

    // The primary purpose of this is to have some sort of fallback for
    // any situation in which the file object has somehow lost its info
    function fileBuilder(googFileObject) {
      if ((googFileObject.mimeType === 'text/plain' && !googFileObject.fileExtension)
          || googFileObject.fileExtension === 'arr') {
        return makeFile(googFileObject, 'text/plain', 'arr');
      } else {
        return makeFile(googFileObject, googFileObject.mimeType, googFileObject.fileExtension);
      }
    }

    var api = {
      getCollectionLink: function() {
        return baseCollection.then(function(bc) {
          return "https://drive.google.com/drive/u/0/folders/" + bc.id;
        });
      },
      getFileById: function(id) {
        return gQ(drive.files.get({fileId: id})).then(fileBuilder);
      },
      getFileByName: function(name) {
        console.log('doing getFileByName ' + name);
        return this.getAllFiles().then(function(files) {
          return files.filter(function(f) { return f.getName() === name });
        });
      },
      getSharedFileById: function(id) {
        return gQ(drive.files.get({fileId: id}), true).then(makeSharedFile);
      },
      getAllFiles: function() {
        return baseCollection.then(function(bc) {
          return gQ(drive.files.list({ q: "trashed=false and '" + bc.id + "' in parents" }))
          .then(function(filesResult) {
            if(!filesResult.items) { return []; }
            return filesResult.items.map(fileBuilder);
          });
        });
      },
      createFile: function(name, opts) {
        opts = opts || {};
        var mimeType = opts.mimeType || 'text/plain';
        var fileExtension = opts.fileExtension || 'arr';
        return baseCollection.then(function(bc) {
          var reqOpts = {
            'path': '/drive/v2/files',
            'method': 'POST',
            'params': opts.params || {},
            'body': {
              'parents': [{id: bc.id}],
              'mimeType': mimeType,
              'title': name
            }
          };
          // Allow the file extension to be omitted
          // (Google can sometime infer from the mime type)
          if (opts.fileExtension !== false) {
            reqOpts.body.fileExtension = fileExtension;
          }
          var request = gapi.client.request(reqOpts);
          return gQ(request).then(fileBuilder);
        });
      },
      checkLogin: function() {
        return collection.then(function() { return true; });
      }
    };

    function findOrCreateShareDirectory() {
      var shareCollectionName = collectionName + ".shared";
      var filesReq = gQ(drive.files.list({
          q: "trashed=false and title = '" + shareCollectionName + "' and "+
             "mimeType = '" + FOLDER_MIME + "'"
        }));
      var collection = filesReq.then(function(files) {
        if(files.items && files.items.length > 0) {
          return files.items[0];
        }
        else {
          var dir = gQ(drive.files.insert({
            resource: {
              mimeType: FOLDER_MIME,
              title: shareCollectionName
            }
          }));
          return dir;
        }
      });
      return collection;
    }

    return {
      api: api,
      collection: baseCollection,
      reinitialize: function() {
        console.log('doing reinitialize');
        return Q.fcall(function() { return initialize(); });
      }
    }
  }

  function initialize() {
    console.log('doing initialize');
    drive = gapi.client.drive;

    if ((typeof drive) === 'undefined') {
      console.log('drive undefined');
      return {
        fail: true
      }
    }

    var list = gQ(drive.files.list({
      q: "trashed=false and title = '" + collectionName + "' and "+
         "mimeType = '" + FOLDER_MIME + "'"
    }));
    console.log('ds26gte list = ' + list);
    var baseCollection = list.then(function(filesResult) {
      console.log('filesResult = ' + filesResult);
      var foundCollection = filesResult.items && filesResult.items[0];
      var baseCollection;
      if(!foundCollection) {
        return gQ(
            drive.files.insert({
              resource: {
                mimeType: "application/vnd.google-apps.folder",
                title: collectionName
              }
            }));
      }
      else {
        return foundCollection;
      }
    });
    var fileList = list.then(function(fr) { return fr.items || []; });
    return createAPI(baseCollection);
  }

  var reauthObsolete = function(immediate) {
    console.log('doing reauth ' + immediate);
    var d = Q.defer();
    /*
    if(!immediate) {
      // Need to do a login to get a cookie for this user; do it in a popup
      var w = window.open("/login?redirect=" + encodeURIComponent("/close.html"));
      window.addEventListener('message', function(e) {
        if (e.domain === document.location.origin) {
          d.resolve(reauth(true));
        } else {
          d.resolve(null);
        }
      });
    }
    else {
      // The user is logged in, but needs an access token from our server
      var newToken = $.ajax("/getAccessToken", { method: "get", datatype: "json" });
      newToken.then(function(t) {
        gapi.auth.setToken({access_token: t.access_token});
        d.resolve({access_token: t.access_token});
      });
      newToken.fail(function(t) {
        d.resolve(null);
      });
    } */
    if (!immediate) {
      console.log('trying gapi.auth.authorize');
      gapi.auth.authorize({
        "client_id": clientId,
        "scope": SCOPE,
        "immediate": true //true
      }, function(authResult) {
        if (authResult && !authResult.error) {
          console.log('ds26gte auth successful');
          console.log('i typeof gapi.client= ' + (typeof gapi.client));
          console.log('i typeof gapi.client.load= ' + (typeof gapi.client.load));
          console.log('i typeof gapi.client.drive= ' + (typeof gapi.client.drive));
          d.resolve(reauth(true)); //why not just d.resolve(true)?
          //d.resolve(true);
        } else {
          console.log('ds26gte auth failed');
          d.resolve(null);
        }
      });
    } else {
      console.log('empty reauth');
      d.resolve(true);
    }
    return d.promise;
  };

  function loadDriveApi() {
    console.log('doing loadDriveApi');
    gapi.client.load('drive', 'v3', listFiles);
  }

  function listFiles() {
    console.log('doing listFiles');
  }

  var reauth = function() {
    console.log('doing reauth');
    var d = Q.defer();
    console.log('trying gapi.auth.authorize');
    gapi.auth.authorize({
      "client_id": clientId,
      "scope": SCOPE,
      "immediate": false
    }, function(authResult) {
      if (authResult && !authResult.error) {
        console.log('ds26gte auth successful');
        console.log('i typeof gapi.client= ' + (typeof gapi.client));
        console.log('i typeof gapi.client.load= ' + (typeof gapi.client.load));
        console.log('i typeof gapi.client.drive= ' + (typeof gapi.client.drive));
        loadDriveApi();
        d.resolve(true);
      } else {
        console.log('ds26gte auth failed');
        d.resolve(null);
      }
    });
    return d.promise;
  }

  //var initialAuth = reauth(immediate);
  var initialAuth = reauth(false);
  console.log('finishing createProgramCollectionAPI');
  return initialAuth.then(function(_) {
    var d = Q.defer();
    console.log('trying gapi.client.load');
    console.log('ii typeof gapi.client= ' + (typeof gapi.client));
    console.log('ii gapi.client= ' + JSON.stringify(gapi.client));
    console.log('ii typeof gapi.client.load= ' + (typeof gapi.client.load));
    console.log('ii typeof gapi.client.drive= ' + (typeof gapi.client.drive));
    /*
    gapi.client.load('drive', 'v3', function() {
      console.log('gapi.client.load calling initialize');
      console.log('iii (shd wk but doesnt) typeof gapi.client.drive= ' + (typeof gapi.client.drive)); //this shouldnt fail
      d.resolve(initialize());
    });
    */
    d.resolve({fail:true});
    return d.promise;
  });
  //console.log('returning second return');
  //return initialAuth;
}
