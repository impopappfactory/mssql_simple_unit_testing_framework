# Simple Unit-testing Framework for MSSQL (T-SQL)

This is a collection of a few simple scripts I wrote for myself while implementing BDD/TDD approach of developing MSSQL-based busuness logic layer.

## The problem

I got used to writing extensive tests for every function I write (in Objective-C or in Swift), and was missing the same possibility while developing for MSSQL. There are quite a few unit-testing frameworks for MSSQL available (...), but none of them appeared simple enough for me. I wanted something really simple I could understand and trust, possibly, for a cost of having to write slightly more complicated tests, with less automation.

## The solution

The solution I finally arrived at consists of the following parts:

* The test suite executor/runner: special stored procedure installed in a separate database schema;
* The suite of tests for every SP/function/trigger.

Test suite executor is invoked with the command:

```SQL
exec test._run_tests
```

It has an optional parameter that allows running specific test case:

```SQL
exec test._run_tests @testcase='test.[testcase trg_iu_chat_message_user_exists aborts insert if user is not participating in chat]'
```

The executor finds all stored procedures in namespace `[test]` with the name matching `testcase%` pattern, and executes each one in a separate transaction. If testcase succeeds, it increases the count of succeeded tests and proceeds to the next testcase. In case of any test failing, the testsuite is terminated. After each testcase is finished either with success or failure, the transaction is rolled back, so any change introduced by running tests does not get into the database. The initial database state is not controlled by the scripts however, so take care of any existing data/primary keys that could prevent tests from being run.

## Samples

Let's assume we'd like to test the following SP:

```SQL
if object_id('dbo.usp_parent_login') is not null
	drop procedure dbo.usp_parent_login
go
create procedure dbo.usp_parent_login
(
	@email varchar(256),
	@pwd_hash varchar(32),

	@sessionid uniqueidentifier out
)
as
	set nocount on
	set xact_abort on

  -- Actual implementation goes here...
go
```

We want to test for possible errors during login process:

```SQL
----------------------------------------------
-- TESTS
----------------------------------------------
if object_id(N'test.[testcase usp_parent_login]') is not null
  drop procedure test.[testcase usp_parent_login]
go
create procedure test.[testcase usp_parent_login]
as
	set nocount on
	set xact_abort on

	declare @retval int

	declare @email varchar(256), @pwd_hash varchar(32)
	set @email='aassatest@aassa.com'
	set @pwd_hash='pwd_hash'

	-- first, register a user
	declare @userid uniqueidentifier
	exec dbo.usp_parent_register @email=@email, @pwd_hash=@pwd_hash, @userid=@userid out

	declare @sessionid uniqueidentifier
	exec @retval = dbo.usp_parent_login @email='unknown', @pwd_hash=@pwd_hash, @sessionid=@sessionid out
	if @retval != dbo.ufn_error_code('user_not_found') OR @sessionid is not null raiserror('unknown email - @sessionid should be nil',16,0)

	exec @retval = dbo.usp_parent_login @email=@email, @pwd_hash='unknown', @sessionid=@sessionid out
	if @retval != dbo.ufn_error_code('user_not_found') OR @sessionid is not null raiserror('unknown password - @sessionid should be nil',16,0)

	exec @retval = dbo.usp_parent_login @email=@email, @pwd_hash=@pwd_hash, @sessionid=@sessionid out
	if @retval != 0 OR @sessionid is null raiserror('@sessionid should not be nil',16,0)

	declare @sessionid2 uniqueidentifier
	exec @retval = dbo.usp_parent_login @email=@email, @pwd_hash=@pwd_hash, @sessionid=@sessionid2 out
	if @retval != 0 OR @sessionid2 is null raiserror('@sessionid2 should not be nil',16,0)
	if @sessionid = @sessionid2 raiserror('@sessionid should not be equal to @sessionid2',16,0)
go

exec test._run_tests @testcase='test.[testcase usp_parent_login]'
```

After execution of `test.[testcase usp_parent_login]` test suite the console output would contain:
```
```

### What if my code (trigger, for example) contains `rollback` or `raiserror` by its own, is it possible to write a test for this case?

Yes, it should be possible.

Let's assume we want to write a test for trigger that could rollback current transaction:

```SQL
if object_id(N'trg_iu_chat_message_user_exists', 'TR') is not null
	drop trigger trg_iu_chat_message_user_exists
go
create trigger trg_iu_chat_message_user_exists
on dbo.chat_message for insert, update
as
	if not exists (select * from dbo.chat_participant cp inner join inserted cm on cp.chatid=cm.chatid inner join dbo.message m on m.messageid=cm.messageid where m.userid=cp.userid) begin
		rollback
		raiserror('there must exist chat_participant with userid = message[messageid=chat_message.messageid].userid',16,0)
		return
	end
go
```

The test suite could look like this:

```SQL
  -- ...
	declare @messageid3_22 uniqueidentifier
	set @messageid3_22 = newid()
	insert dbo.message(messageid,userid,timestamp) values(@messageid3_22,@userid_child3,getutcdate())
	declare @was_error3_22 bit
	begin try
  	-- attempt to insert message from child3 to the chat of child2 with parent2 --> should FAIL
		insert dbo.chat_message(chatid,messageid) values(dbo.ufn_user_chat(@userid_child2,@userid_parent2),@messageid3_22)
	end try
	begin catch
		set @was_error3_22 = 1
	end catch
	if isnull(@was_error3_22,0) != 1 raiserror('expected to raise error(child3 posting to chat(child2,parent2))',16,0)
	if exists(select * from dbo.chat_message where chatid=dbo.ufn_user_chat(@userid_child2,@userid_parent2) and messageid=@messageid3_22) raiserror('expected to abort posting of @messageid3_22',16,0)
  -- ...
```

...And, for testing the code which invokes `raiserror`, e.g.:

```SQL
```

the test could look like:

```SQL
```

## Disclaimer

