# Set up nginx? The connection to the reverb server needs to be
# configured app-side? I.e. we don't provide any additional location
# (/app) to the virtualHost from here

{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
with lib;
with types;

let
  cfg = config.services.laravel-reverb;
  pkgs-master = import /etc/nixos/modules/nixpkgs-master { config = {}; overlays = []; };
  # We need the phpRedis extension even if redis is not locally served?
  redisEnabled = cfg.envConfig.CACHE_STORE == "redis";
  php' = if redisEnabled then
    pkgs-master.php.buildEnv {
      extensions = { enabled, all }: with all; enabled ++ [ redis ];
    }
         else pkgs-master.php;
  laravel-reverb = (pkgs-master.callPackage ./package.nix { }).override { php = php'; };
  format = pkgs.formats.json { };
in
{
  options.services.laravel-reverb = {
    enable = mkEnableOption "Reverb: A WebSocket server built with PHP & Laravel";

    user = mkOption {
      type = str;
      default = "reverb";
      description = "User reverb runs as.";
    };

    group = mkOption {
      type = str;
      default = "reverb";
      description = "Group reverb runs as.";
    };

    hostName = mkOption {
      type = str;
      description = "Hostname where the instance is reachable.";
    };

    provisionNginx = mkOption {
      type = bool;
      default = true;
      example = false;
      description = "Whether to use Nginx as the reverse proxy.";
    };

    envConfig = mkOption {
      example = literalExpression ''
        {
          DB_USERNAME = "root";
        }
      '';
      description = ''
        Configuration parameters to set in
        {file}`.env`.
      '';

      type = submodule {
        # TODO: Expand this section, also allow more types than
        # string?
        freeformType = attrsOf str;

        options = {

          # APP_KEY = mkOption {
          #   type = with types; nullOr str;
          #   default = null;
          # };

          CACHE_STORE = mkOption {
            type = enum [
              "array"
              "redis"
            ];
            default = "array";
          };

          REDIS_HOST = mkOption {
            type = str;
            default = "unix:///run/redis-reverb/redis.sock";
          };

          REDIS_PORT = mkOption {
            type = port;
            # default = cfg.redis.port;
            default = 0;
          };

          LOG_CHANNEL = mkOption {
            type = str;
            default = "syslog";
          };
        };
      };
    };

    reverbConfig =
      let
        secret = submodule {
          options = {
            _secret = mkOption {
              type = externalPath;
            };
            quote = mkOption {
              type = bool;
              default = true;
            };
          };
        };
      in
      mkOption {
      example = literalExpression ''
        {
          servers.reverb = {
            host = "127.0.0.1";
          };
          apps = [
            {
              app_id = "my-app-id";
              key = "my-app-key";
              secret = { _secret = "/path/to/secret"; };
            };
          ];
        }
      '';
      description = ''
        Configuration parameters to be set in accordance
        with {file}`config/reverb.php`.
      '';

      type = submodule {
        freeformType = format.type;

        options = {
          default = mkOption {
            default = "reverb";
            internal = true;
            readOnly = true;
          };

          servers.reverb = {
            host = mkOption {
              type = str;
              default = "127.0.0.1";
              example = "0.0.0.0";
              description = ''
                The IP address the server should bind to.
              '';
            };
            port = mkOption {
              type = port;
              default = 8080;
              description = ''
                The port the server should listen on.
              '';
            };
            path = mkOption {
              type = str;
              default = "";
              example = "/reverb";
              description = ''
                The path the server should prefix to all routes.
              '';
            };
            hostname = mkOption {
              type = str;
              default = cfg.hostName;
              example = "reverb.example.com";
              description = ''
                The hostname the server is accessible from.
              '';
            };
            max_request_size = mkOption {
              type = int;
              default = 10000;
            };
            scaling = {
              enabled = mkOption {
                type = bool;
                default = false;
              };
              channel = mkOption {
                default = "reverb";
              };

   #             'server' => [
   #                 'url' => env('REDIS_URL'),
   #                 'host' => env('REDIS_HOST', '127.0.0.1'),
   #                 'port' => env('REDIS_PORT', '6379'),
   #                 'username' => env('REDIS_USERNAME'),
   #                 'password' => env('REDIS_PASSWORD'),
   #                 'database' => env('REDIS_DB', '0'),
   #                 'timeout' => env('REDIS_TIMEOUT', 60),
   #             ],
            };
            pulse_ingest_interval = mkOption {
              type = int;
              default = 15;
            };
            telescope_ingest_interval = mkOption {
              type = int;
              default = 15;
            };
          };
          apps = {
            # Is this also something we should set and hide?
            provider = mkOption {
              type = str;
              default = "config";
            };
            apps = mkOption {

              type = nonEmptyListOf (submodule {

                freeformType = attrs;

                options = {
                  key = mkOption {
                    type = str;
                  };
                  app_id = mkOption {
                    type = str;
                  };
                  secret = mkOption {
                    type = coercedTo externalPath (x: { _secret = toString x; }) secret;
                    description = ''
                      Always handled as a secret whether the value is
                      wrapped in a `{ _secret = ...; }`
                      attrset or not.
                    '';
                  };

                  # options = {
                  #   host = mkOption {
                  #     type = str;
                  #     example = "wss.laravel.org";
                  #   };
                  #   port = mkOption {
                  #     type = port;
                  #     default = 443;
                  #   };
                  #   scheme = mkOption {
                  #     type = enum[
                  #       "http"
                  #       "https"
                  #     ];
                  #     default = "https";
                  #   };
                  #   useTLS = mkOption {
                  #     type = bool;
                  #     default = true;
                  #   };
                  # };
                  allowed_origins = mkOption {
                    type = listOf str;
                    default = [ "*" ];
                  };
                  ping_interval = mkOption {
                    type = int;
                    default = 60;
                  };
                  activity_timeout = mkOption {
                    type = int;
                    default = 30;
                  };
                  # max_connections =
                  max_message_size = mkOption {
                    type = int;
                    default = 10000;
                  };
                  accept_client_events_from = mkOption {
                    type = str;
                    default = "members";
                  };
                  #               'rate_limiting' => [
                  #                   'enabled' => env('REVERB_APP_RATE_LIMITING_ENABLED', false),
                  #                   'max_attempts' => env('REVERB_APP_RATE_LIMIT_MAX_ATTEMPTS', 60),
                  #                   'decay_seconds' => env('REVERB_APP_RATE_LIMIT_DECAY_SECONDS', 60),
                  #                   'terminate_on_limit' => env('REVERB_APP_RATE_LIMIT_TERMINATE', false),
                  #               ],


                };
              });
            };
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {

    # # If the redis host given is localhost/127.0.0.1, we enable the
    # # redis server on the host
    # services.redis.servers.reverb =
    #   mkIf
    #     (cfg.settings.CACHE_STORE == "redis" &&
    #      elem cfg.redis.host [
    #        "localhost"
    #        "127.0.0.1"
    #      ])
    #     {
    #       enable = true;
    #       bind = cfg.redis.host;
    #       # Port should probably be 0 (default) so that we can use the unix
    #       # socket if on localhost
    #       port = cfg.redis.port;
    #     };

    systemd.services.laravel-reverb = mkMerge
      [
        {
          description = "WebSocket server Laravel Reverb";

          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "exec";
            User = cfg.user;

            RuntimeDirectory = "laravel-reverb";
            CacheDirectory = "laravel-reverb/bootstrap/cache";
            WorkingDirectory = "${laravel-reverb}/share/php/laravel-reverb";

            ExecStartPre =
            let
              # isSecret = v: isAttrs v && v ? _secret && (isString v._secret || builtins.isPath v._secret);
              reverbEnvVars = generators.toKeyValue {
                mkKeyValue = flip generators.mkKeyValueDefault "=" {
                  mkValueString =
                    v:
                    with builtins;
                    if isInt v then
                      toString v
                    else if isString v then
                      "\"${v}\""
                    else if true == v then
                      "true"
                    else if false == v then
                      "false"
                    else if isSecret v then
                      if (isString v._secret) then
                        hashString "sha256" v._secret
                      else
                        hashString "sha256" (builtins.readFile v._secret)
                    else
                      throw "unsupported type ${typeOf v}: ${(generators.toPretty { }) v}";
                };
              };
              # secretPaths = mapAttrsToList (_: v: v._secret) (filterAttrs (_: isSecret) cfg.config);
              # mkSecretReplacement = file: ''
              #   replace-secret ${
              #     escapeShellArgs [
              #       (
              #         if (isString file) then
              #           builtins.hashString "sha256" file
              #         else
              #           builtins.hashString "sha256" (builtins.readFile file)
              #       )
              #       file
              #       "${cfg.dataDir}/.env"
              #     ]
              #   }
              # '';
              # secretReplacements = concatMapStrings mkSecretReplacement secretPaths;
              filteredConfig = converge (filterAttrsRecursive (
                _: v:
                !elem v [
                  { }
                  null
                ]
              )) cfg.envConfig;
              reverbEnvFile = pkgs.writeText "reverb.env" (reverbEnvVars filteredConfig);

              # reverbConfigFile = format.generate "reverbConfig.json" cfg.reverbConfig;

              secretsReplacement = utils.genJqSecretsReplacement {
                # loadCredential = true;
              } cfg.reverbConfig "/run/laravel-reverb/reverbConfig.json";
            in
              pkgs.writeShellScript "reverb-setup" ''
                # error handling
                set -euo pipefail

                # set permissions
                umask 077

                # create .env file
                install -T -m 0600 -o ${cfg.user} ${reverbEnvFile} "/run/laravel-reverb/.env"
                ${secretsReplacement.script}
              '';

            ExecStart = ''
              ${getExe php'} artisan reverb:start
            '';
          };


        }
        (mkIf redisEnabled
          {
            after = [ "redis-reverb.service" ];
            wants = [ "redis-reverb.service" ];
          }
        )
      ];

    users = {
      users = mkIf (cfg.user == "reverb") {
        reverb = {
          group = "reverb";
          isSystemUser = true;
          extraGroups = [ "redis-reverb" ];
        };
      };
      groups = mkIf (cfg.group == "reverb") {
        reverb = { };
      };
    };

    services.nginx = mkIf cfg.provisionNginx {
      enable = true;
      recommendedProxySettings = mkDefault true;

      virtualHosts.${cfg.hostName} = {
        locations."${cfg.reverbConfig.servers.reverb.path}/app" = {
          proxyWebsockets = true;
          proxyPass = "http://${cfg.reverbConfig.servers.reverb.host}:${toString cfg.reverbConfig.servers.reverb.port}";
        };
      };
    };
  };
}
