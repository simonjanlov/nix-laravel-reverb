# Handle .env, reverb.php
# Set up redis
# Define a systemd unit that runs
# php artisan reverb:start and handles local directories

# Set up nginx? The connection to the reverb server needs to be
# configured app-side? I.e. we don't provide any additional location
# (/app) to the virtualHost from here


{
  config,
  options,
  lib,
  pkgs,
  ...
}:
with lib;

let
  cfg = config.services.laravel-reverb;
  opt = options.services.laravel-reverb;
  pkgs-master = import /etc/nixos/modules/nixpkgs-master { config = {}; overlays = []; };
  redisEnabled = cfg.settings.CACHE_STORE == "redis";
  php' = if redisEnabled then
    pkgs-master.php.buildEnv {
      extensions = { enabled, all }: with all; enabled ++ [ redis ];
    }
         else pkgs-master.php;
  laravel-reverb = (pkgs-master.callPackage ./package.nix { }).override { php = php'; };
in
{
  options.services.laravel-reverb = {
    enable = mkEnableOption "Reverb: A WebSocket server built with PHP & Laravel";

    user = mkOption {
      default = "reverb";
      description = "User reverb runs as.";
      type = types.str;
    };

    group = mkOption {
      default = "reverb";
      description = "Group reverb runs as.";
      type = types.str;
    };

    redis = {
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = ''
            Redis server hostname.
          '';
        };

        port  = mkOption {
          type = types.int;
          # Should probably always be 0? If we're not setting redis
          # host to localhost we won't be hosting the redis server at
          # all (?)
          default = if (cfg.redis.host == "localhost" || cfg.redis.host == "127.0.0.1") then 0 else 6379;
          description = ''
            Redis server port.
          '';
        };

        passwordFile = mkOption {
          type = with types; nullOr path;
          default = null;
          description = ''
            File containing the Redis password.

            This should be a string, not a nix path, since nix paths are
            copied into the world-readable nix store.
          '';
        };

        dbNumber = mkOption {
          type = types.int;
          default = 0;
          description = ''
            Redis database number.
          '';
        };

        useSSL = mkOption {
          type = types.bool;
          default = cfg.redis.host != "localhost";
          defaultText = literalExpression ''config.${opt.redis.host} != "localhost"'';
          description = ''
            Connect to Redis with SSL.
          '';
        };
    };

    settings = mkOption {
      # example = literalExpression ''
      #   {
      #     imap = {
      #       host = "imap.example.com";
      #       user = "alice@example.com";
      #       password = { _secret = "/run/keys/imap_password" };
      #     };
      #     mailbox = {
      #       watch = true;
      #       batch_size = 30;
      #     };
      #     splunk_hec = {
      #       url = "https://splunkhec.example.com";
      #       token = { _secret = "/run/keys/splunk_token" };
      #       index = "email";
      #     };
      #   }
      # '';
      description = ''
        Configuration parameters to set in
        {file}`.env`.
      '';

      type = types.submodule {
        freeformType = with types; attrsOf str;

        options = {

          APP_KEY = mkOption {
            type = with types; nullOr str;
            default = null;
          };

          REVERB_SERVER_HOST = mkOption {
            type = types.str;
            default = "127.0.0.1";
          };

          REVERB_SERVER_PORT = mkOption {
            type = types.port;
            default = 8080;
          };

          CACHE_STORE = mkOption {
            type = types.enum [
              "array"
              "redis"
            ];
            default = "array";
          };

          REDIS_HOST = mkOption {
            type = types.str;
            default = "unix:///run/redis-reverb/redis.sock";
          };

          REDIS_PORT = mkOption {
            type = types.port;
            default = cfg.redis.port;
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {

    ## TEMP
    # Get anything out of laravel-reverb, to trigger the build
    environment.etc = {
      # Creates /etc/test
      test = {
        text = ''
          whatever you want to put in the file goes here.
          ${laravel-reverb}
        '';
        mode = "0440";
      };
    };


    # If the redis host given is localhost/127.0.0.1, we enable the
    # redis server on the host
    services.redis.servers.reverb =
      mkIf
        (elem cfg.redis.host [
          "localhost"
          "127.0.0.1"
        ])
        {
          enable = true;
          bind = cfg.redis.host;
          # Port should probably be 0 (default) so that we can use the unix
          # socket if on localhost
          port = cfg.redis.port;
        };

    systemd.services.reverb-setup = mkMerge
      [
        {
          description = "Preparation tasks for Laravel Reverb";

          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = cfg.user;

            # TEMP (for manual install of reverb.php)
            StateDirectory = "laravel-reverb";

            # We don't actually need persistent storage for laravel
            # reverb but we need the config files to persist over
            # service restarts
            RuntimeDirectory = "laravel-reverb";
            RuntimeDirectoryPreserve = "yes";

            WorkingDirectory = "${laravel-reverb}/share/php/laravel-reverb";
          };
          # path = [
          #   pkgs.replace-secret
          #   artisan
          # ];
          script =
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
              )) cfg.settings;
              reverbEnv = pkgs.writeText "reverb.env" (reverbEnvVars filteredConfig);
            in
              ''
                # error handling
                set -euo pipefail

                # set permissions
                umask 077

                # create .env file
                install -T -m 0600 -o ${cfg.user} ${reverbEnv} "/run/laravel-reverb/.env"
              '';
        }
        (mkIf redisEnabled
          {
            after = [ "redis-reverb.service" ];
            wants = [ "redis-reverb.service" ];
          }
        )
      ];

    # If you change the user, you're on your own
    users = {
      users = mkIf (cfg.user == "reverb") {
        reverb = {
          group = "reverb";
          isSystemUser = true;
        };
      };
      groups = mkIf (cfg.group == "reverb") {
        reverb = { };
      };
    };
  };
}
