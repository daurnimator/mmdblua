# mmdblua

A Lua library for reading [MaxMind's Geolocation database format](https://maxmind.github.io/MaxMind-DB/).

This project had it's initial development sprint done in a hotel room during the [Lua Workshop 2013](https://www.lua.org/wshop13.html).


# Installation

mmdblua is available from [luarocks](https://luarocks.org/).

    $ luarocks install mmdblua


# Development

## Getting started

  - Clone the repo:
    ```
    $ git clone --recursive https://github.com/daurnimator/mmdblua.git
    $ cd mmdblua
    ```
    *Note that mmdblua has a git submodule for test data.*

  - Lint the code (check for common programming errors)
    ```
    $ luacheck .
    ```

  - Run tests
    ```
    $ busted
    ```

  - Install your local copy:
    ```
    $ luarocks make mmdblua-scm-0.rockspec
    ```
