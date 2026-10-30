process.env.NODE_ENV = process.env.NODE_ENV || 'production'

const CompressionPlugin = require("compression-webpack-plugin");
const TerserPlugin = require("terser-webpack-plugin");
const environment = require('./environment')

environment.plugins.prepend(
    "Compression",
    new CompressionPlugin({
        filename: "[path].br[query]",
        algorithm: "brotliCompress",
        test: /\.(ts|tsx|js|jsx|css|scss|png|jpeg|jpg|svg|eot|woff|woff2|ttf|otf)$/,
        compressionOptions: { level: 11 },
        threshold: 10240,
        minRatio: 0.8,
        deleteOriginalAssets: false,
    })
);

environment.config.merge({
    devtool: "hidden-source-map",
    optimization: {
        minimizer: [
            new TerserPlugin({
                extractComments: false,
                parallel: true,
                cache: true,
                sourceMap: false,
                terserOptions: {
                    parse: {
                        ecma: 8,
                    },
                    compress: {
                        ecma: 5,
                        warnings: false,
                        comparisons: false,
                    },
                    mangle: {
                        safari10: true,
                    },
                    output: {
                        ecma: 5,
                        comments: false,
                        ascii_only: true,
                    },
                },
            }),
        ],
    },
});

environment.config.output.publicPath = `https://${process.env.APP_HOST}/packs/`

module.exports = environment.toWebpackConfig()
