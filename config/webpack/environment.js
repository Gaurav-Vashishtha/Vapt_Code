const { environment } = require('@rails/webpacker')
const erb = require('./loaders/erb')

const customConfig = require('./custom')

environment.config.output.jsonpFunction = 'birdChimeCODJsonpFunction'

environment.config.merge(customConfig)

environment.loaders.prepend('erb', erb)

environment.config.merge({
    externals: {
      lodash: 'commonjs lodash',
    },
  });

// default config from https://webpack.js.org/plugins/split-chunks-plugin/#optimizationsplitchunks
environment.splitChunks((config) =>
    Object.assign({}, config, {
        optimization: {
            runtimeChunk: false,
            splitChunks: {
                // chunks: 'all', // changed to all
                chunks(chunk) {
                  // exclude `my-excluded-chunk`
                  return (chunk.name !== 'script_react' && chunk.name !== 'script_react_new' && chunk.name!=='order_verify_react' && chunk.name!=='order_prepaid_react');
                },
                minSize: 30000,
                maxSize: 0,
                minChunks: 1,
                maxAsyncRequests: 30, // changed
                maxInitialRequests: 30, // changed
                automaticNameDelimiter: '~',
                automaticNameMaxLength: 30,
                name: true,
                cacheGroups: {
                    vendors: {
                        test: /[\\/]node_modules[\\/]/,
                        priority: -10
                    },
                    default: {
                        minChunks: 2,
                        priority: -20,
                        reuseExistingChunk: true
                    }
                }
            }
        },
    })
);

module.exports = environment
