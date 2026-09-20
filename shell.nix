{ pkgs ? import <nixpkgs> { } }:

# Reproducible local development environment for the discourse-taper
# plugin. The plugin itself doesn't need a DB to run — Discourse boots
# it via a separate checkout — but the linters and `bundle install`
# need ruby + the native libs gems compile against.
#
# Usage:
#   nix-shell             # drops you into a shell with ruby + bundler
#   bundle install        # installs gems into ./.gems (gitignored)
#   bundle exec rubocop
#   bundle exec stree check $(git ls-files '*.rb') Gemfile
#
# To run the plugin's specs you still need to symlink the plugin into
# a Discourse checkout and run rspec from there:
#   ln -s $PWD ~/discourse/discourse/plugins/discourse-taper

pkgs.mkShell {
  buildInputs = with pkgs; [
    ruby_3_3
    bundler

    # Native build deps for common gems
    pkg-config
    openssl
    libyaml
    zlib
    libffi

    # `pg` gem needs pg_config at install time even if we never connect
    postgresql
  ];

  shellHook = ''
    # Isolate gem installs to the repo so they don't leak into ~/.gem
    # or collide with other Ruby projects on this machine.
    export GEM_HOME="$PWD/.gems"
    export PATH="$GEM_HOME/bin:$PATH"
    export BUNDLE_PATH="$GEM_HOME"
  '';
}
