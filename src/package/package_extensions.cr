class Zap::Package
  struct PackageExtension
    include JSON::Serializable

    getter dependencies : Hash(String, String?)? = nil
    @[JSON::Field(key: "optionalDependencies")]
    getter optional_dependencies : Hash(String, String?)? = nil
    @[JSON::Field(key: "peerDependencies")]
    getter peer_dependencies : Hash(String, String?)? = nil
    @[JSON::Field(key: "peerDependenciesMeta")]
    getter peer_dependencies_meta : Hash(String, {optional: Bool?}?)? = nil

    def merge_into(pkg : Package)
      dependencies.try &.each do |name, version|
        if version.nil?
          pkg.dependencies.try &.delete(name)
        else
          hash = (pkg.dependencies ||= SafeHash(String, String).new)
          hash[name] = version
        end
      end
      optional_dependencies.try &.each do |name, version|
        if version.nil?
          pkg.optional_dependencies.try &.delete(name)
        else
          hash = (pkg.optional_dependencies ||= SafeHash(String, String).new)
          hash[name] = version
        end
      end
      peer_dependencies.try &.each do |name, version|
        if version.nil?
          pkg.peer_dependencies.try &.delete(name)
        else
          hash = (pkg.peer_dependencies ||= SafeHash(String, String).new)
          hash[name] = version
        end
      end
      peer_dependencies_meta.try &.each do |name, value|
        if value.nil?
          pkg.peer_dependencies_meta.try &.delete(name)
        else
          hash = (pkg.peer_dependencies_meta ||= SafeHash(String, {optional: Bool?}).new)
          hash[name] = value
        end
      end
    end

    # See: https://github.com/yarnpkg/berry/blob/master/packages/yarnpkg-extensions/sources/index.ts
    PACKAGE_EXTENSIONS = Array({String, PackageExtension}).from_json(%(
      [
        [
          "@tailwindcss/aspect-ratio@<0.2.1",
          {
            "peerDependencies": {
              "tailwindcss": "^2.0.2"
            }
          }
        ],
        [
          "@tailwindcss/line-clamp@<0.2.1",
          {
            "peerDependencies": {
              "tailwindcss": "^2.0.2"
            }
          }
        ],
        [
          "@fullhuman/postcss-purgecss@3.1.3 || 3.1.3-alpha.0",
          {
            "peerDependencies": {
              "postcss": "^8.0.0"
            }
          }
        ],
        [
          "@samverschueren/stream-to-observable@<0.3.1",
          {
            "peerDependenciesMeta": {
              "rxjs": {
                "optional": true
              },
              "zenObservable": {
                "optional": true
              }
            }
          }
        ],
        [
          "any-observable@<0.5.1",
          {
            "peerDependenciesMeta": {
              "rxjs": {
                "optional": true
              },
              "zenObservable": {
                "optional": true
              }
            }
          }
        ],
        [
          "@pm2/agent@<1.0.4",
          {
            "dependencies": {
              "debug": "*"
            }
          }
        ],
        [
          "debug@<4.2.0",
          {
            "peerDependenciesMeta": {
              "supports-color": {
                "optional": true
              }
            }
          }
        ],
        [
          "got@<11",
          {
            "dependencies": {
              "@types/responselike": "^1.0.0",
              "@types/keyv": "^3.1.1"
            }
          }
        ],
        [
          "cacheable-lookup@<4.1.2",
          {
            "dependencies": {
              "@types/keyv": "^3.1.1"
            }
          }
        ],
        [
          "http-link-dataloader@*",
          {
            "peerDependencies": {
              "graphql": "^0.13.1 || ^14.0.0"
            }
          }
        ],
        [
          "typescript-language-server@*",
          {
            "dependencies": {
              "vscode-jsonrpc": "^5.0.1",
              "vscode-languageserver-protocol": "^3.15.0"
            }
          }
        ],
        [
          "postcss-syntax@*",
          {
            "peerDependenciesMeta": {
              "postcss-html": {
                "optional": true
              },
              "postcss-jsx": {
                "optional": true
              },
              "postcss-less": {
                "optional": true
              },
              "postcss-markdown": {
                "optional": true
              },
              "postcss-scss": {
                "optional": true
              }
            }
          }
        ],
        [
          "jss-plugin-rule-value-function@<=10.1.1",
          {
            "dependencies": {
              "tiny-warning": "^1.0.2"
            }
          }
        ],
        [
          "ink-select-input@<4.1.0",
          {
            "peerDependencies": {
              "react": "^16.8.2"
            }
          }
        ],
        [
          "license-webpack-plugin@<2.3.18",
          {
            "peerDependenciesMeta": {
              "webpack": {
                "optional": true
              }
            }
          }
        ],
        [
          "snowpack@>=3.3.0",
          {
            "dependencies": {
              "node-gyp": "^7.1.0"
            }
          }
        ],
        [
          "promise-inflight@*",
          {
            "peerDependenciesMeta": {
              "bluebird": {
                "optional": true
              }
            }
          }
        ],
        [
          "reactcss@*",
          {
            "peerDependencies": {
              "react": "*"
            }
          }
        ],
        [
          "react-color@<=2.19.0",
          {
            "peerDependencies": {
              "react": "*"
            }
          }
        ],
        [
          "gatsby-plugin-i18n@*",
          {
            "dependencies": {
              "ramda": "^0.24.1"
            }
          }
        ],
        [
          "useragent@^2.0.0",
          {
            "dependencies": {
              "request": "^2.88.0",
              "yamlparser": "0.0.x",
              "semver": "5.5.x"
            }
          }
        ],
        [
          "@apollographql/apollo-tools@<=0.5.2",
          {
            "peerDependencies": {
              "graphql": "^14.2.1 || ^15.0.0"
            }
          }
        ],
        [
          "material-table@^2.0.0",
          {
            "dependencies": {
              "@babel/runtime": "^7.11.2"
            }
          }
        ],
        [
          "@babel/parser@*",
          {
            "dependencies": {
              "@babel/types": "^7.8.3"
            }
          }
        ],
        [
          "fork-ts-checker-webpack-plugin@<=6.3.4",
          {
            "peerDependencies": {
              "eslint": ">= 6",
              "typescript": ">= 2.7",
              "webpack": ">= 4",
              "vue-template-compiler": "*"
            },
            "peerDependenciesMeta": {
              "eslint": {
                "optional": true
              },
              "vue-template-compiler": {
                "optional": true
              }
            }
          }
        ],
        [
          "rc-animate@<=3.1.1",
          {
            "peerDependencies": {
              "react": ">=16.9.0",
              "react-dom": ">=16.9.0"
            }
          }
        ],
        [
          "react-bootstrap-table2-paginator@*",
          {
            "dependencies": {
              "classnames": "^2.2.6"
            }
          }
        ],
        [
          "react-draggable@<=4.4.3",
          {
            "peerDependencies": {
              "react": ">= 16.3.0",
              "react-dom": ">= 16.3.0"
            }
          }
        ],
        [
          "apollo-upload-client@<14",
          {
            "peerDependencies": {
              "graphql": "14 - 15"
            }
          }
        ],
        [
          "react-instantsearch-core@<=6.7.0",
          {
            "peerDependencies": {
              "algoliasearch": ">= 3.1 < 5"
            }
          }
        ],
        [
          "react-instantsearch-dom@<=6.7.0",
          {
            "dependencies": {
              "react-fast-compare": "^3.0.0"
            }
          }
        ],
        [
          "ws@<7.2.1",
          {
            "peerDependencies": {
              "bufferutil": "^4.0.1",
              "utf-8-validate": "^5.0.2"
            },
            "peerDependenciesMeta": {
              "bufferutil": {
                "optional": true
              },
              "utf-8-validate": {
                "optional": true
              }
            }
          }
        ],
        [
          "react-portal@<4.2.2",
          {
            "peerDependencies": {
              "react-dom": "^15.0.0-0 || ^16.0.0-0 || ^17.0.0-0"
            }
          }
        ],
        [
          "react-scripts@<=4.0.1",
          {
            "peerDependencies": {
              "react": "*"
            }
          }
        ],
        [
          "testcafe@<=1.10.1",
          {
            "dependencies": {
              "@babel/plugin-transform-for-of": "^7.12.1",
              "@babel/runtime": "^7.12.5"
            }
          }
        ],
        [
          "testcafe-legacy-api@<=4.2.0",
          {
            "dependencies": {
              "testcafe-hammerhead": "^17.0.1",
              "read-file-relative": "^1.2.0"
            }
          }
        ],
        [
          "@google-cloud/firestore@<=4.9.3",
          {
            "dependencies": {
              "protobufjs": "^6.8.6"
            }
          }
        ],
        [
          "gatsby-source-apiserver@*",
          {
            "dependencies": {
              "babel-polyfill": "^6.26.0"
            }
          }
        ],
        [
          "@webpack-cli/package-utils@<=1.0.1-alpha.4",
          {
            "dependencies": {
              "cross-spawn": "^7.0.3"
            }
          }
        ],
        [
          "gatsby-remark-prismjs@<3.3.28",
          {
            "dependencies": {
              "lodash": "^4"
            }
          }
        ],
        [
          "gatsby-plugin-favicon@*",
          {
            "peerDependencies": {
              "webpack": "*"
            }
          }
        ],
        [
          "gatsby-plugin-sharp@<=4.6.0-next.3",
          {
            "dependencies": {
              "debug": "^4.3.1"
            }
          }
        ],
        [
          "gatsby-react-router-scroll@<=5.6.0-next.0",
          {
            "dependencies": {
              "prop-types": "^15.7.2"
            }
          }
        ],
        [
          "@rebass/forms@*",
          {
            "dependencies": {
              "@styled-system/should-forward-prop": "^5.0.0"
            },
            "peerDependencies": {
              "react": "^16.8.6"
            }
          }
        ],
        [
          "rebass@*",
          {
            "peerDependencies": {
              "react": "^16.8.6"
            }
          }
        ],
        [
          "@ant-design/react-slick@<=0.28.3",
          {
            "peerDependencies": {
              "react": ">=16.0.0"
            }
          }
        ],
        [
          "mqtt@<4.2.7",
          {
            "dependencies": {
              "duplexify": "^4.1.1"
            }
          }
        ],
        [
          "vue-cli-plugin-vuetify@<=2.0.3",
          {
            "dependencies": {
              "semver": "^6.3.0"
            },
            "peerDependenciesMeta": {
              "sass-loader": {
                "optional": true
              },
              "vuetify-loader": {
                "optional": true
              }
            }
          }
        ],
        [
          "vue-cli-plugin-vuetify@<=2.0.4",
          {
            "dependencies": {
              "null-loader": "^3.0.0"
            }
          }
        ],
        [
          "vue-cli-plugin-vuetify@>=2.4.3",
          {
            "peerDependencies": {
              "vue": "*"
            }
          }
        ],
        [
          "@vuetify/cli-plugin-utils@<=0.0.4",
          {
            "dependencies": {
              "semver": "^6.3.0"
            },
            "peerDependenciesMeta": {
              "sass-loader": {
                "optional": true
              }
            }
          }
        ],
        [
          "@vue/cli-plugin-typescript@<=5.0.0-alpha.0",
          {
            "dependencies": {
              "babel-loader": "^8.1.0"
            }
          }
        ],
        [
          "@vue/cli-plugin-typescript@<=5.0.0-beta.0",
          {
            "dependencies": {
              "@babel/core": "^7.12.16"
            },
            "peerDependencies": {
              "vue-template-compiler": "^2.0.0"
            },
            "peerDependenciesMeta": {
              "vue-template-compiler": {
                "optional": true
              }
            }
          }
        ],
        [
          "cordova-ios@<=6.3.0",
          {
            "dependencies": {
              "underscore": "^1.9.2"
            }
          }
        ],
        [
          "cordova-lib@<=10.0.1",
          {
            "dependencies": {
              "underscore": "^1.9.2"
            }
          }
        ],
        [
          "git-node-fs@*",
          {
            "peerDependencies": {
              "js-git": "^0.7.8"
            },
            "peerDependenciesMeta": {
              "js-git": {
                "optional": true
              }
            }
          }
        ],
        [
          "consolidate@<0.16.0",
          {
            "peerDependencies": {
              "mustache": "^3.0.0"
            },
            "peerDependenciesMeta": {
              "mustache": {
                "optional": true
              }
            }
          }
        ],
        [
          "consolidate@<=0.16.0",
          {
            "peerDependencies": {
              "velocityjs": "^2.0.1",
              "tinyliquid": "^0.2.34",
              "liquid-node": "^3.0.1",
              "jade": "^1.11.0",
              "then-jade": "*",
              "dust": "^0.3.0",
              "dustjs-helpers": "^1.7.4",
              "dustjs-linkedin": "^2.7.5",
              "swig": "^1.4.2",
              "swig-templates": "^2.0.3",
              "razor-tmpl": "^1.3.1",
              "atpl": ">=0.7.6",
              "liquor": "^0.0.5",
              "twig": "^1.15.2",
              "ejs": "^3.1.5",
              "eco": "^1.1.0-rc-3",
              "jazz": "^0.0.18",
              "jqtpl": "~1.1.0",
              "hamljs": "^0.6.2",
              "hamlet": "^0.3.3",
              "whiskers": "^0.4.0",
              "haml-coffee": "^1.14.1",
              "hogan.js": "^3.0.2",
              "templayed": ">=0.2.3",
              "handlebars": "^4.7.6",
              "underscore": "^1.11.0",
              "lodash": "^4.17.20",
              "pug": "^3.0.0",
              "then-pug": "*",
              "qejs": "^3.0.5",
              "walrus": "^0.10.1",
              "mustache": "^4.0.1",
              "just": "^0.1.8",
              "ect": "^0.5.9",
              "mote": "^0.2.0",
              "toffee": "^0.3.6",
              "dot": "^1.1.3",
              "bracket-template": "^1.1.5",
              "ractive": "^1.3.12",
              "nunjucks": "^3.2.2",
              "htmling": "^0.0.8",
              "babel-core": "^6.26.3",
              "plates": "~0.4.11",
              "react-dom": "^16.13.1",
              "react": "^16.13.1",
              "arc-templates": "^0.5.3",
              "vash": "^0.13.0",
              "slm": "^2.0.0",
              "marko": "^3.14.4",
              "teacup": "^2.0.0",
              "coffee-script": "^1.12.7",
              "squirrelly": "^5.1.0",
              "twing": "^5.0.2"
            },
            "peerDependenciesMeta": {
              "velocityjs": {
                "optional": true
              },
              "tinyliquid": {
                "optional": true
              },
              "liquid-node": {
                "optional": true
              },
              "jade": {
                "optional": true
              },
              "then-jade": {
                "optional": true
              },
              "dust": {
                "optional": true
              },
              "dustjs-helpers": {
                "optional": true
              },
              "dustjs-linkedin": {
                "optional": true
              },
              "swig": {
                "optional": true
              },
              "swig-templates": {
                "optional": true
              },
              "razor-tmpl": {
                "optional": true
              },
              "atpl": {
                "optional": true
              },
              "liquor": {
                "optional": true
              },
              "twig": {
                "optional": true
              },
              "ejs": {
                "optional": true
              },
              "eco": {
                "optional": true
              },
              "jazz": {
                "optional": true
              },
              "jqtpl": {
                "optional": true
              },
              "hamljs": {
                "optional": true
              },
              "hamlet": {
                "optional": true
              },
              "whiskers": {
                "optional": true
              },
              "haml-coffee": {
                "optional": true
              },
              "hogan.js": {
                "optional": true
              },
              "templayed": {
                "optional": true
              },
              "handlebars": {
                "optional": true
              },
              "underscore": {
                "optional": true
              },
              "lodash": {
                "optional": true
              },
              "pug": {
                "optional": true
              },
              "then-pug": {
                "optional": true
              },
              "qejs": {
                "optional": true
              },
              "walrus": {
                "optional": true
              },
              "mustache": {
                "optional": true
              },
              "just": {
                "optional": true
              },
              "ect": {
                "optional": true
              },
              "mote": {
                "optional": true
              },
              "toffee": {
                "optional": true
              },
              "dot": {
                "optional": true
              },
              "bracket-template": {
                "optional": true
              },
              "ractive": {
                "optional": true
              },
              "nunjucks": {
                "optional": true
              },
              "htmling": {
                "optional": true
              },
              "babel-core": {
                "optional": true
              },
              "plates": {
                "optional": true
              },
              "react-dom": {
                "optional": true
              },
              "react": {
                "optional": true
              },
              "arc-templates": {
                "optional": true
              },
              "vash": {
                "optional": true
              },
              "slm": {
                "optional": true
              },
              "marko": {
                "optional": true
              },
              "teacup": {
                "optional": true
              },
              "coffee-script": {
                "optional": true
              },
              "squirrelly": {
                "optional": true
              },
              "twing": {
                "optional": true
              }
            }
          }
        ],
        [
          "vue-loader@<=16.3.3",
          {
            "peerDependencies": {
              "@vue/compiler-sfc": "^3.0.8",
              "webpack": "^4.1.0 || ^5.0.0-0"
            },
            "peerDependenciesMeta": {
              "@vue/compiler-sfc": {
                "optional": true
              }
            }
          }
        ],
        [
          "vue-loader@^16.7.0",
          {
            "peerDependencies": {
              "@vue/compiler-sfc": "^3.0.8",
              "vue": "^3.2.13"
            },
            "peerDependenciesMeta": {
              "@vue/compiler-sfc": {
                "optional": true
              },
              "vue": {
                "optional": true
              }
            }
          }
        ],
        [
          "scss-parser@<=1.0.5",
          {
            "dependencies": {
              "lodash": "^4.17.21"
            }
          }
        ],
        [
          "query-ast@<1.0.5",
          {
            "dependencies": {
              "lodash": "^4.17.21"
            }
          }
        ],
        [
          "redux-thunk@<=2.3.0",
          {
            "peerDependencies": {
              "redux": "^4.0.0"
            }
          }
        ],
        [
          "skypack@<=0.3.2",
          {
            "dependencies": {
              "tar": "^6.1.0"
            }
          }
        ],
        [
          "@npmcli/metavuln-calculator@<2.0.0",
          {
            "dependencies": {
              "json-parse-even-better-errors": "^2.3.1"
            }
          }
        ],
        [
          "bin-links@<2.3.0",
          {
            "dependencies": {
              "mkdirp-infer-owner": "^1.0.2"
            }
          }
        ],
        [
          "rollup-plugin-polyfill-node@<=0.8.0",
          {
            "peerDependencies": {
              "rollup": "^1.20.0 || ^2.0.0"
            }
          }
        ],
        [
          "snowpack@<3.8.6",
          {
            "dependencies": {
              "magic-string": "^0.25.7"
            }
          }
        ],
        [
          "elm-webpack-loader@*",
          {
            "dependencies": {
              "temp": "^0.9.4"
            }
          }
        ],
        [
          "winston-transport@<=4.4.0",
          {
            "dependencies": {
              "logform": "^2.2.0"
            }
          }
        ],
        [
          "jest-vue-preprocessor@*",
          {
            "dependencies": {
              "@babel/core": "7.8.7",
              "@babel/template": "7.8.6"
            },
            "peerDependencies": {
              "pug": "^2.0.4"
            },
            "peerDependenciesMeta": {
              "pug": {
                "optional": true
              }
            }
          }
        ],
        [
          "redux-persist@*",
          {
            "peerDependencies": {
              "react": ">=16"
            },
            "peerDependenciesMeta": {
              "react": {
                "optional": true
              }
            }
          }
        ],
        [
          "sodium@>=3",
          {
            "dependencies": {
              "node-gyp": "^3.8.0"
            }
          }
        ],
        [
          "babel-plugin-graphql-tag@<=3.1.0",
          {
            "peerDependencies": {
              "graphql": "^14.0.0 || ^15.0.0"
            }
          }
        ],
        [
          "@playwright/test@<=1.14.1",
          {
            "dependencies": {
              "jest-matcher-utils": "^26.4.2"
            }
          }
        ],
        [
          "babel-plugin-remove-graphql-queries@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "babel-preset-gatsby-package@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "create-gatsby@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-admin@<0.24.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-cli@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-core-utils@<2.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-design-tokens@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-legacy-polyfills@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-benchmark-reporting@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-graphql-config@<0.23.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-image@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-mdx@<2.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-netlify-cms@<5.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-no-sourcemaps@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-page-creator@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-preact@<5.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-preload-fonts@<2.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-schema-snapshot@<2.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-styletron@<6.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-subfont@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-plugin-utils@<1.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-recipes@<0.25.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-source-shopify@<5.6.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-source-wikipedia@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-transformer-screenshot@<3.14.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-worker@<0.5.0-next.1",
          {
            "dependencies": {
              "@babel/runtime": "^7.14.8"
            }
          }
        ],
        [
          "gatsby-core-utils@<2.14.0-next.1",
          {
            "dependencies": {
              "got": "8.3.2"
            }
          }
        ],
        [
          "gatsby-plugin-gatsby-cloud@<=3.1.0-next.0",
          {
            "dependencies": {
              "gatsby-core-utils": "^2.13.0-next.0"
            }
          }
        ],
        [
          "gatsby-plugin-gatsby-cloud@<=3.2.0-next.1",
          {
            "peerDependencies": {
              "webpack": "*"
            }
          }
        ],
        [
          "babel-plugin-remove-graphql-queries@<=3.14.0-next.1",
          {
            "dependencies": {
              "gatsby-core-utils": "^2.8.0-next.1"
            }
          }
        ],
        [
          "gatsby-plugin-netlify@3.13.0-next.1",
          {
            "dependencies": {
              "gatsby-core-utils": "^2.13.0-next.0"
            }
          }
        ],
        [
          "clipanion-v3-codemod@<=0.2.0",
          {
            "peerDependencies": {
              "jscodeshift": "^0.11.0"
            }
          }
        ],
        [
          "react-live@*",
          {
            "peerDependencies": {
              "react-dom": "*",
              "react": "*"
            }
          }
        ],
        [
          "webpack@<4.44.1",
          {
            "peerDependenciesMeta": {
              "webpack-cli": {
                "optional": true
              },
              "webpack-command": {
                "optional": true
              }
            }
          }
        ],
        [
          "webpack@<5.0.0-beta.23",
          {
            "peerDependenciesMeta": {
              "webpack-cli": {
                "optional": true
              }
            }
          }
        ],
        [
          "webpack-dev-server@<3.10.2",
          {
            "peerDependenciesMeta": {
              "webpack-cli": {
                "optional": true
              }
            }
          }
        ],
        [
          "@docusaurus/responsive-loader@<1.5.0",
          {
            "peerDependenciesMeta": {
              "sharp": {
                "optional": true
              },
              "jimp": {
                "optional": true
              }
            }
          }
        ],
        [
          "eslint-module-utils@*",
          {
            "peerDependenciesMeta": {
              "eslint-import-resolver-node": {
                "optional": true
              },
              "eslint-import-resolver-typescript": {
                "optional": true
              },
              "eslint-import-resolver-webpack": {
                "optional": true
              },
              "@typescript-eslint/parser": {
                "optional": true
              }
            }
          }
        ],
        [
          "eslint-plugin-import@*",
          {
            "peerDependenciesMeta": {
              "@typescript-eslint/parser": {
                "optional": true
              }
            }
          }
        ],
        [
          "critters-webpack-plugin@<3.0.2",
          {
            "peerDependenciesMeta": {
              "html-webpack-plugin": {
                "optional": true
              }
            }
          }
        ],
        [
          "terser@<=5.10.0",
          {
            "dependencies": {
              "acorn": "^8.5.0"
            }
          }
        ],
        [
          "babel-preset-react-app@10.0.x",
          {
            "dependencies": {
              "@babel/plugin-proposal-private-property-in-object": "^7.16.0"
            }
          }
        ],
        [
          "eslint-config-react-app@*",
          {
            "peerDependenciesMeta": {
              "typescript": {
                "optional": true
              }
            }
          }
        ],
        [
          "@vue/eslint-config-typescript@<11.0.0",
          {
            "peerDependenciesMeta": {
              "typescript": {
                "optional": true
              }
            }
          }
        ],
        [
          "unplugin-vue2-script-setup@<0.9.1",
          {
            "peerDependencies": {
              "@vue/composition-api": "^1.4.3",
              "@vue/runtime-dom": "^3.2.26"
            }
          }
        ],
        [
          "@cypress/snapshot@*",
          {
            "dependencies": {
              "debug": "^3.2.7"
            }
          }
        ],
        [
          "auto-relay@<=0.14.0",
          {
            "peerDependencies": {
              "reflect-metadata": "^0.1.13"
            }
          }
        ],
        [
          "vue-template-babel-compiler@<1.2.0",
          {
            "peerDependencies": {
              "vue-template-compiler": "^2.6.0"
            }
          }
        ],
        [
          "@parcel/transformer-image@<2.5.0",
          {
            "peerDependencies": {
              "@parcel/core": "*"
            }
          }
        ],
        [
          "@parcel/transformer-js@<2.5.0",
          {
            "peerDependencies": {
              "@parcel/core": "*"
            }
          }
        ],
        [
          "parcel@*",
          {
            "peerDependenciesMeta": {
              "@parcel/core": {
                "optional": true
              }
            }
          }
        ],
        [
          "react-scripts@*",
          {
            "peerDependencies": {
              "eslint": "*"
            }
          }
        ],
        [
          "focus-trap-react@^8.0.0",
          {
            "dependencies": {
              "tabbable": "^5.3.2"
            }
          }
        ],
        [
          "react-rnd@<10.3.7",
          {
            "peerDependencies": {
              "react": ">=16.3.0",
              "react-dom": ">=16.3.0"
            }
          }
        ],
        [
          "connect-mongo@*",
          {
            "peerDependencies": {
              "express-session": "^1.17.1"
            }
          }
        ],
        [
          "vue-i18n@<9",
          {
            "peerDependencies": {
              "vue": "^2"
            }
          }
        ],
        [
          "vue-router@<4",
          {
            "peerDependencies": {
              "vue": "^2"
            }
          }
        ],
        [
          "unified@<10",
          {
            "dependencies": {
              "@types/unist": "^2.0.0"
            }
          }
        ],
        [
          "react-github-btn@<=1.3.0",
          {
            "peerDependencies": {
              "react": ">=16.3.0"
            }
          }
        ],
        [
          "react-dev-utils@*",
          {
            "peerDependencies": {
              "typescript": ">=2.7",
              "webpack": ">=4"
            },
            "peerDependenciesMeta": {
              "typescript": {
                "optional": true
              }
            }
          }
        ],
        [
          "@asyncapi/react-component@<=1.0.0-next.39",
          {
            "peerDependencies": {
              "react": ">=16.8.0",
              "react-dom": ">=16.8.0"
            }
          }
        ],
        [
          "xo@*",
          {
            "peerDependencies": {
              "webpack": ">=1.11.0"
            },
            "peerDependenciesMeta": {
              "webpack": {
                "optional": true
              }
            }
          }
        ],
        [
          "babel-plugin-remove-graphql-queries@<=4.20.0-next.0",
          {
            "dependencies": {
              "@babel/types": "^7.15.4"
            }
          }
        ],
        [
          "gatsby-plugin-page-creator@<=4.20.0-next.1",
          {
            "dependencies": {
              "fs-extra": "^10.1.0"
            }
          }
        ],
        [
          "gatsby-plugin-utils@<=3.14.0-next.1",
          {
            "dependencies": {
              "fastq": "^1.13.0"
            },
            "peerDependencies": {
              "graphql": "^15.0.0"
            }
          }
        ],
        [
          "gatsby-plugin-mdx@<3.1.0-next.1",
          {
            "dependencies": {
              "mkdirp": "^1.0.4"
            }
          }
        ],
        [
          "gatsby-plugin-mdx@^2",
          {
            "peerDependencies": {
              "gatsby": "^3.0.0-next"
            }
          }
        ],
        [
          "fdir@<=5.2.0",
          {
            "peerDependencies": {
              "picomatch": "2.x"
            },
            "peerDependenciesMeta": {
              "picomatch": {
                "optional": true
              }
            }
          }
        ],
        [
          "babel-plugin-transform-typescript-metadata@<=0.3.2",
          {
            "peerDependencies": {
              "@babel/core": "^7",
              "@babel/traverse": "^7"
            },
            "peerDependenciesMeta": {
              "@babel/traverse": {
                "optional": true
              }
            }
          }
        ],
        [
          "graphql-compose@>=9.0.10",
          {
            "peerDependencies": {
              "graphql": "^14.2.0 || ^15.0.0 || ^16.0.0"
            }
          }
        ]
      ]
    ))
  end
end
