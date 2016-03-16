{-#LANGUAGE QuasiQuotes #-}
{-#LANGUAGE RankNTypes #-}
module Database.YeshQL.SimulationTests
( tests
)
where

import Test.Tasty
import Test.Tasty.HUnit
import Database.HDBC
import Database.HDBC.Mock
import Database.YeshQL
import System.IO
import Data.Char
import Data.List (dropWhile, dropWhileEnd)

tests =
    [ testSimpleSelect
    , testParametrizedSelect
    , testSingleInsert
    , testUpdateReturnRowCount
    , testMultiQuery
    , testQueryFromFile
    , testQueryFromFileAutoName
    , testManyQueriesFromFileAutoName
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

testParametrizedSelect :: TestTree
testParametrizedSelect = testCase "Parametrized SELECT" $ chatTest chatScript $ \conn -> do
    actual <- [yesh|
        -- name:getUserByName :: (Integer, String)
        -- :username :: String
        SELECT id, username FROM users WHERE username = :username|] "billy" conn
    let expected :: [(Integer, String)]
        expected = [(1, "billy")]
    assertEqual "" expected actual
    where
        chatScript =
            [ ChatStep
                { chatQuery = sameThrough trim "SELECT id, username FROM users WHERE username = ?"
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
    let expected :: [Integer]
        expected = [23]
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
        -- name:renameUser :: Integer
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
    ;
    -- name:setUserName :: Integer
    -- :userID :: Int
    -- :username :: String
    UPDATE users SET username = :username WHERE id = :userID
|]

testMultiQuery :: TestTree
testMultiQuery = testCase "Define multiple queries in one QQ inside a where" $ chatTest chatScript $ \conn -> do
    [userID] <- findUser "billy" conn
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

chatTest :: [ChatStep] -> (forall conn. IConnection conn => conn -> IO ()) -> Assertion
chatTest chatScript action =
    newChatConnection chatScript >>= action

trim :: String -> String
trim = dropWhile isSpace . dropWhileEnd isSpace