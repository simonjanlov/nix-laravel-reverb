{
  runtimeDir ? "/run/laravel-reverb",
  dataDir ? "/var/lib/laravel-reverb",
  cacheDir ? "/var/cache/laravel-reverb",
  fetchFromGitHub,
  php,
}:

php.buildComposerProject2 (finalAttrs: {
  pname = "laravel-reverb";
  version = "1.12.0";

  src = fetchFromGitHub {
    owner = "laravel";
    repo = "laravel";
    tag = "v13.10.1";
    hash = "sha256-/3zrDesB4JJRBLgssmm0wtMHL6XpA0nSCN9WlEPiB0M=";
  };

  # This currently depends on a local bugfix in nixpkgs
  # composerVendor to inherit patches in build-composer-project.nix
  patches = [ ./composer.json.patch ];

  composerLock = ./composer.lock;

  vendorHash = "sha256-VMDX7R62CjbQHAZvM7Zgwp9nnoj6gjrgk1o6zqTsP3o=";

  postInstall = ''
    reverb_out="$out/share/php/laravel-reverb"

    rm -R $reverb_out/storage $reverb_out/bootstrap/cache

    ln -s ${runtimeDir}/.env $reverb_out/.env
    # ln -s ${runtimeDir}/reverb.php $reverb_out/config/reverb.php
    # Temporary, while the below file is copied in manually
    ln -s ${dataDir}/reverb.php $reverb_out/config/reverb.php
    ln -s ${cacheDir}/bootstrap/cache $reverb_out/bootstrap/cache

  '';

  meta = {
    description = "WebSocket server Laravel Reverb";
    longDescription = ''
      Laravel Reverb brings real-time WebSocket communication for Laravel applications.

      Details: https://reverb.laravel.com/.
    '';
    homepage = "https://reverb.laravel.com/";
    # changelog = "";
    # license = "";
    # maintainers = with lib.maintainers; [ ];
    # platforms = lib.platforms.linux;
  };
})
