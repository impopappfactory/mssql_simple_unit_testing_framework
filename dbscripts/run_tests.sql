-----------------------------------------------------
-- run tests


if object_id(N'test.[_run_tests]') is not null
	drop procedure test.[_run_tests]
go
create procedure test.[_run_tests]
(
	@testcase nvarchar(max) = NULL -- pass to execute given testcase
)
as
	set nocount on
	set xact_abort on

	print '---------------------------------------'
	print 'RUNNING TESTS'
	print ''

	declare @name sysname
	declare @sql nvarchar(4000)
	set @sql = N''
	declare cr cursor local read_only static forward_only for
		select o.[name] from sys.objects o
		where
			o.[type] = 'P'
			and SCHEMA_NAME(o.[schema_id]) = 'test'
			and o.[object_id] = isnull(object_id(@testcase), o.[object_id])

	declare @tests_count int
	set @tests_count = 0

	open cr
	fetch next from cr into @name
	while @@FETCH_STATUS = 0
	begin
		if @name like 'testcase%' begin
			set @tests_count = @tests_count + 1
			print 'Running testcase: test.[' + @name + ']...'
			set @sql =
				N'begin try'+CHAR(13)+
				N'begin tran testcase'+CHAR(13)+
				N'exec test.['+@name+N']'+CHAR(13)+
				N'end try'+CHAR(13)+
				N'begin catch'+CHAR(13)+
				N'	declare @error int, @message varchar(4000)'+CHAR(13)+
				N'	select @error = ERROR_NUMBER(), @message = ERROR_MESSAGE()'+CHAR(13)+
				N'	if @error != 266 or @@trancount != 0 raiserror(@message,16,0)'+CHAR(13)+				N'end catch'+CHAR(13)+
				N'if @@trancount > 0 rollback tran testcase'+CHAR(13)+
				N''
			--print @sql
			exec( @sql )
			print 'DONE'
			print ''
		end
		fetch next from cr into @name
	end
	close cr
	deallocate cr
	
	print ''
	print ltrim(str(@tests_count)) + ' TESTS DONE'
	print '---------------------------------------'
	
go 

exec test.[_run_tests]
go
