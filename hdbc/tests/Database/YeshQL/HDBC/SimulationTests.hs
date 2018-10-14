{-#LANGUAGE QuasiQuotes #-}
{-#LANGUAGE RankNTypes #-}
{-#LANGUAGE LambdaCase #-}
{-#LANGUAGE TemplateHaskell #-}
module Database.YeshQL.HDBC.SimulationTests
( tests
)
where

import Test.Tasty
import Test.Tasty.HUnit
import Database.HDBC
import Database.HDBC.Mock
import Database.YeshQL.HDBC
import Database.YeshQL.HDBC.SqlRow.Class
import Database.YeshQL.HDBC.SqlRow.TH
import System.IO
import Data.Char
import Data.List (dropWhile, dropWhileEnd)

data User =
    User
        { userID :: Int
        , userName :: String
        }
        deriving (Show, Eq)
makeSqlRow ''User

data Person =
    Person
        { personName :: String
        , personEmail :: String
        }
        deriving (Show, Eq)
makeSqlRow ''Person

data UserData =
    UserData
        { user :: User
        , person :: Person
        }
        deriving (Show, Eq)

instance ToSqlRow UserData where
    toSqlRow d = (toSqlRow . user $ d) ++ (toSqlRow . person $ d)

instance FromSqlRow UserData where
    parseSqlRow = UserData <$> parseSqlRow <*> parseSqlRow

tests =
    [ testSimpleSelect
    , testSimpleSelectStr
    , testParametrizedSelect
    , testSingleInsert
    , testRecordReturn
    , testRecordReturnComplex
    , testRecordReturnExcessive
    , testRecordParams
    , testUpdateReturnRowCount
    , testMultiQuery
    , testQueryFromFile
    , testQueryFromFileAutoName
    , testManyQueriesFromFileAutoName
    , testDDL
    ]

testSimpleSelect :: TestTree
testSimpleSelect = testCase "Simple SELECT" $ chatTest chatScript $ \conn -> do
    results <- [yesh|
        -- name:getUserByName :: (String)
        SELECT username FROM users|] conn
    return ()
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT username FROM users"
                , chatParams = []
                , chatResultSet = []
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testEmptyReturn :: TestTree
testEmptyReturn = testCase "Simple SELECT (empty return)" $ chatTest chatScript $ \conn -> do
    [yesh|
        -- name:getUserByName :: ()
        SELECT username FROM users WHERE 0|] conn
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT username FROM users WHERE 0"
                , chatParams = []
                , chatResultSet = []
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testSimpleSelectStr :: TestTree
testSimpleSelectStr = testCase "Simple SELECT (expr by string)" $ chatTest chatScript $ \conn -> do
    results <- $(yesh $ unlines
        [ "-- name:getUserByName :: (String)"
        , "SELECT username FROM users"
        ]) conn
    return ()
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT username FROM users"
                , chatParams = []
                , chatResultSet = []
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testParametrizedSelect :: TestTree
testParametrizedSelect = testCase "Parametrized SELECT" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: (Integer, String)
        -- :username :: String
        SELECT id, username FROM users WHERE username = :username LIMIT 1|] "billy" conn
    let expected :: Maybe (Integer, String)
        expected = Just (1, "billy")
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username FROM users WHERE username = ? LIMIT 1"
                , chatParams = [exactly (toSql "billy")]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy"]]
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testRecordReturn :: TestTree
testRecordReturn = testCase "Return record from SELECT" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: User
        -- :username :: String
        SELECT id, username FROM users WHERE username = :username LIMIT 1|]
        "billy"
        conn
    let expected :: Maybe User
        expected = Just $ User 1 "billy"
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username FROM users WHERE username = ? LIMIT 1"
                , chatParams = [exactly (toSql "billy")]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy"]]
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testRecordReturnComplex :: TestTree
testRecordReturnComplex = testCase "Return record from SELECT" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: UserData
        -- :username :: String
        SELECT id, username, person_name, email FROM users WHERE username = :username LIMIT 1|]
        "billy"
        conn
    let expected :: Maybe UserData
        expected = Just $ UserData (User 1 "billy") (Person "Billy" "billy@example.org")
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username, person_name, email FROM users WHERE username = ? LIMIT 1"
                , chatParams = [exactly (toSql "billy")]
                , chatResultSet =
                    [
                        [ toSql (1 :: Int)
                        , toSql "billy"
                        , toSql "Billy"
                        , toSql "billy@example.org"
                        ]
                    ]
                , chatColumnNames = ["username", "person_name", "email"]
                , chatRowsAffected = 0
                }
            ]

testRecordReturnExcessive :: TestTree
testRecordReturnExcessive = testCase "Return record from SELECT (extra values ignored)" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: User
        -- :username :: String
        SELECT id, username FROM users WHERE username = :username LIMIT 1|]
        "billy"
        conn
    let expected :: Maybe User
        expected = Just $ User 1 "billy"
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username FROM users WHERE username = ? LIMIT 1"
                , chatParams = [exactly (toSql "billy")]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy", toSql "willie"]]
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testRecordParams :: TestTree
testRecordParams = testCase "Pass records as params" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: User
        -- :user :: User
        SELECT id, username FROM users WHERE username = :user.userName.reverse LIMIT 1|]
        (User 10 "yllib")
        conn
    let expected :: Maybe User
        expected = Just $ User 1 "billy"
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username FROM users WHERE username = ? LIMIT 1"
                , chatParams = [exactly (toSql "billy")]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy"]]
                , chatColumnNames = ["username"]
                , chatRowsAffected = 0
                }
            ]

testSingleInsert :: TestTree
testSingleInsert = testCase "Single INSERT" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:createUser :: (Integer)
        -- :username :: String
        INSERT INTO users (username) VALUES (:username) RETURNING id|] "billy" conn
    let expected :: Maybe Integer
        expected = Just 23
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "INSERT INTO users (username) VALUES (?) RETURNING id"
                , chatParams = [exactly $ toSql "billy"]
                , chatResultSet = [[toSql (23 :: Int)]]
                , chatColumnNames = ["id"]
                , chatRowsAffected = 1
                }
            ]

testUpdateReturnRowCount :: TestTree
testUpdateReturnRowCount = testCase "UPDATE, get row count" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:renameUser :: rowcount Integer
        -- :oldName :: String
        -- :newName :: String
        UPDATE users SET username = :oldName WHERE username = :newName AND username <> :oldName|]
            "tony" "billy" conn
    let expected :: Integer
        expected = 1
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim
                    "UPDATE users SET username = ? WHERE username = ? AND username <> ?"
                , chatParams =
                    [ exactly $ toSql "tony"
                    , exactly $ toSql "billy"
                    , exactly $ toSql "tony"
                    ]
                , chatResultSet = []
                , chatColumnNames = []
                , chatRowsAffected = 1
                }
            ]

[yesh|
    -- name:findUser :: (Int)
    -- :username :: String
    SELECT id FROM users WHERE username = :username
    ;;;
    -- name:setUserName :: rowcount Integer
    -- :userID :: Int
    -- :username :: String
    UPDATE users SET username = :username WHERE id = :userID
|]

testMultiQuery :: TestTree
testMultiQuery = testCase "Define multiple queries in one QQ inside a where" $ chatTest chatScript $ \conn -> do
    userID <- maybe (fail "User Not Found") return =<< findUser "billy" conn
    rowCount <- setUserName userID "tony" conn
    assertEqual "" rowCount 1
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim
                    "SELECT id FROM users WHERE username = ?"
                , chatParams =
                    [ exactly $ toSql "billy"
                    ]
                , chatResultSet = [[toSql (1 :: Int)]]
                , chatColumnNames = ["id"]
                , chatRowsAffected = 0
                }
            , ChatStep
                { chatQuery = sameThrough trim
                    "UPDATE users SET username = ? WHERE id = ?"
                , chatParams =
                    [ exactly $ toSql "tony"
                    , exactly $ toSql (1 :: Int)
                    ]
                , chatResultSet = []
                , chatColumnNames = []
                , chatRowsAffected = 1
                }
            ]

testQueryFromFile :: TestTree
testQueryFromFile = testCase "Query loaded from fixture file" $
        chatTest chatScript $ \conn -> do
            [(userID, username)] <- [yesh1File|tests/fixtures/getUserNamed.sql|] 1 conn
            assertEqual "" userID 1
            assertEqual "" username "billy"
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim
                    "SELECT id, username FROM users WHERE id = ?"
                , chatParams =
                    [ exactly $ toSql (1 :: Int)
                    ]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy"]]
                , chatColumnNames = ["id", "username"]
                , chatRowsAffected = 0
                }
            ]

[yesh1File|tests/fixtures/getUser.sql|]

testQueryFromFileAutoName :: TestTree
testQueryFromFileAutoName = testCase "Query loaded from fixture file, deriving query name from filename" $
        chatTest chatScript $ \conn -> do
            [(userID, username)] <- getUser 1 conn
            assertEqual "" userID 1
            assertEqual "" username "billy"
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim
                    "SELECT id, username FROM users WHERE id = ?"
                , chatParams =
                    [ exactly $ toSql (1 :: Int)
                    ]
                , chatResultSet = [[toSql (1 :: Int), toSql "billy"]]
                , chatColumnNames = ["id", "username"]
                , chatRowsAffected = 0
                }
            ]

[yeshFile|tests/fixtures/multiQueries.sql|]

testManyQueriesFromFileAutoName :: TestTree
testManyQueriesFromFileAutoName = testCase "Many queries from fixture file, auto-naming some" $
        chatTest chatScript $ \conn -> do
            count0 <- multiQueries_0 conn
            count1 <- multiQueriesNamed conn
            count2 <- multiQueries_2 conn
            assertEqual "" count0 1
            assertEqual "" count1 2
            assertEqual "" count2 3
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim
                    "BLAH"
                , chatParams =
                    []
                , chatResultSet = []
                , chatColumnNames = []
                , chatRowsAffected = 1
                }
            , ChatStep
                { chatQuery = sameThrough trim
                    "PIZZA"
                , chatParams =
                    []
                , chatResultSet = []
                , chatColumnNames = []
                , chatRowsAffected = 2
                }
            , ChatStep
                { chatQuery = sameThrough trim
                    "OLIVES"
                , chatParams =
                    []
                , chatResultSet = []
                , chatColumnNames = []
                , chatRowsAffected = 3
                }
            ]

testDDL :: TestTree
testDDL = testCase "typical DDL statement sequence" $
        chatTest chatScript
        [yesh1|
            -- @ddl
            CREATE TABLE users
                ( id INTEGER
                , username TEXT
                );
            CREATE TABLE pages
                ( id INTEGER
                , owner_id INTEGER
                , title TEXT
                , body TEXT
                , FOREIGN KEY (owner_id) REFERENCES users (id)
                );
        |]
        where
            chatScript =
                [ ChatStep
                    { chatQuery = anything
                    , chatParams = []
                    , chatResultSet = []
                    , chatColumnNames = []
                    , chatRowsAffected = 0
                    }
                ]

chatTest :: [ChatStep] -> (forall conn. IConnection conn => conn -> IO ()) -> Assertion
chatTest chatScript action =
    newChatConnection chatScript >>= action

trim :: String -> String
trim = dropWhile isSpace . dropWhileEnd isSpace
