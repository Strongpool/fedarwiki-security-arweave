###
 * Federated Wiki : Node Server
 *
 * Copyright Ward Cunningham and other contributors
 * Licensed under the MIT license.
 * https://github.com/fedwiki/wiki-node-server/blob/master/LICENSE.txt
###
# **security.coffee**
# Module for Arweave site security.

#### Requires ####
console.log 'friends starting'
crypto = require 'crypto'
fs = require 'fs'
seedrandom = require 'seedrandom'
Arweave = require 'arweave'


# Export a function that generates security handler
# when called with options object.
module.exports = exports = (log, loga, argv) ->
  security = {}

  #### Private utility methods. ####

  user = ''
  owner = ''
  admin = argv.admin

  # save the location of the identity file
  idFile = argv.id

  arweave = Arweave.init({
    host: 'arweave.net'
    port: 1984,
    protocol: 'https'})

  #### Public stuff ####

  # Retrieve owner infomation from identity file in status directory
  # owner will contain { address: <address> }
  security.retrieveOwner = (cb) ->
    fs.exists idFile, (exists) ->
      if exists
        fs.readFile(idFile, (err, data) ->
          if err then return cb err
          owner = JSON.parse(data)
          cb())
      else
        owner = ''
        cb()

  # Return the owners name
  security.getOwner = getOwner = ->
    if !owner.address?
      ownerName = ''
    else
      ownerName = owner.address
    ownerName

  security.setOwner = setOwner = (id, cb) ->
    owner = id
    fs.exists idFile, (exists) ->
      if !exists
        fs.writeFile(idFile, JSON.stringify(id, null, "  "), (err) ->
          if err then return cb err
          console.log "Claiming site for ", id:id
          owner = id
          cb())
      else
        cb()

  security.getUser = (req) ->
    if req.session.address
      return req.session.address
    else
      return ''

  security.isAuthorized = (req) ->
    try
      if req.session.address is owner.address
        return true
      else
        return false
    catch error
      return false

  # Wiki server admin
  security.isAdmin = (req) ->
    if req.session.address is admin
      return true
    else
      return false

  security.login = (updateOwner) ->
    (req, res) ->
      try
        rawTx = req.body.tx
        tx = arweave.transactions.fromRaw rawTx
        verified = await arweave.transactions.verify tx
        address = arweave.utils.bufferTob64Url(
          crypto
            .createHash('sha256')
            .update(arweave.utils.b64UrlToBuffer(rawTx.owner))
            .digest())
      catch error
        console.log 'Failed to verify transaction ', req.hostname, 'error ', error
        res.sendStatus(500)

      if owner is '' # site is not claimed
        if verified
          req.session.address = address
          id = { address: address }
          setOwner id, (err) ->
            if err
              console.log 'Failed to claim wiki ', req.hostname, 'error ', err
              res.sendStatus(500)
            updateOwner getOwner
            res.json { ownerName: address }
            res.end
        else
          res.sendStatus(401)
      else
        if verified and owner.address is address
          req.session.address = owner.address
          res.end()
        else
          res.sendStatus(401)

        console.log 'Arweave returning login'

  security.logout = () ->
    (req, res) ->
      req.session.reset()
      res.send('OK')

  security.defineRoutes = (app, cors, updateOwner) ->
    app.post '/login', cors, security.login(updateOwner)
    app.get '/logout', cors, security.logout()

  security
