# YeshQL

[YesQL](https://github.com/krisajenkins/yesql)-style SQL database abstraction.

YeshQL implements quasiquoters that allow the programmer to write SQL queries
in SQL, and embed these into Haskell programs using quasi-quotation. YeshQL
takes care of generating suitable functions that will run the SQL queries
against a HDBC database driver, and marshal values between Haskell and SQL.

In order to do this properly, YeshQL extends SQL syntax with type annotations
and function names; other than that, it is perfectly ignorant about the SQL
syntax itself. See the [YesQL
Readme](https://github.com/krisajenkins/yesql/blob/master/README.md) for the
full rationale - Haskell and Clojure are sufficiently different languages, but
the reasoning behind YesQL applies to YeshQL almost unchanged.

## Installation

Use [stack](http://haskellstack.org/) or [cabal](http://haskell.org/cabal/) to
install. Nothing extraordinary here.

## Usage

In short:

    {-#LANGUAGE QuasiQuotes #-}
    import MyProject.DatabaseConnection (withDB)
    import Database.HDBC
    import Database.YeshQL

    [yesh|
      -- name:getUser :: (String)
      -- :userID :: Int
      SELECT username FROM users WHERE id = :userID
    |] 

    main = withDB $ \conn -> do
      username <- getUser 1 conn
      putStrLn username

Please refer to the Haddock documentation for further usage details.

## Bugs

Probably. The project is hosted at https://github.com/tdammers/yeshql, feel
free to comment there or send a message to tdammers@gmail.com if you find any.

## Something about the name

YeshQL is rather heavily inspired by YesQL, so it makes sense to blatantly
steal most of the name. Throwing in an "H" for good measure (this being Haskell
and all) makes it sound like Sean Connery, which automatically increases
aweshomenesh, so that'sh what we'll roll with.

## License / Copying

YeshQL is Free Software and provided as-is. Please see the enclosed LICENSE
file for details.

## Legacy / Backwards-Compatibility Notice

**Note** that the `yeshql` package, starting with the 4.1 release, is now
merely a wrapper around `yeshql-core` and `yeshql-hdbc`, re-exporting what is
hopefully close enough to the original `yeshql` API to be somewhat compatible.

This is because starting with this release, `yeshql` has been split up into a
frontend, which takes care of query parsing and the whole TemplateHaskell
machinery, and several backends - at the time of writing, these are
`yeshql-hdbc`, which uses HDBC just like the original `yeshql` package, and
`yeshql-postgresql-simpel`, which uses `postgresql-simple`. With this
architecture, it is possible to add more backends without affecting the
frontend or any of the other backends.
