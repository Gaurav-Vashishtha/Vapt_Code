process.env.NODE_ENV = process.env.NODE_ENV || 'test'

const environment = require('./environment')

environment.config.output.publicPath = `https://${process.env.APP_HOST}/packs/`

module.exports = environment.toWebpackConfig()
