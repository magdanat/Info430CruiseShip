/* Doris ---- Stored Procedures */
USE CRUISE

/* SP: Get CustBookingID */
CREATE PROCEDURE getCustBookID
@CustFname VARCHAR(50),
@CustLname VARCHAR(50),
@CustDOB Date,
@BookingNum char(7),
@CustBookID INT OUTPUT
AS
    SET @CustBookID = (
        SELECT CustBookingID FROM tblCUST_BOOK CB
            JOIN tblCUSTOMER C ON CB.CustID = C.CustID
            JOIN tblBOOKING B ON CB.BookingID = B.BookingID
        WHERE C.CustFname = @CustFname
            AND C.CustLname = @CustLname
            AND C.CustDOB = @CustDOB
            AND B.BookingNumber = @BookingNum
        )
GO

/* SP: Get ExcursionTripID */
CREATE PROCEDURE getExcurTripID
@ShipName varchar(50),
@TripStartDate Date,
@TripEndDate Date,
@ExcurName varchar(225),
@ExcurTripStartTime Datetime,
@ExcurTripEndTime Datetime,
@ExcurTripID INT OUTPUT
AS
    SET @ExcurTripID = (
        SELECT ET.ExcursionTripID FROM tblTRIP T
            JOIN tblCRUISESHIP C ON T.CruiseshipID = C.CruiseshipID
            JOIN tblEXCURSION_TRIP ET on T.TripID = ET.TripID
            JOIN tblEXCURSION E ON ET.ExcursionID = E.ExcursionID
        WHERE C.CruiseshipName = @ShipName
            AND T.StartDate = @TripStartDate
            AND T.EndDate = @TripEndDate
            AND E.ExcursionName = @ExcurName
            AND ET.StartTime = @ExcurTripStartTime
            AND ET.EndTime = @ExcurTripEndTime
        )
GO


/* SP 1
    Add new row in tblCUST_BOOK_EXC_TRIP */
CREATE PROCEDURE sp_insertCUST_BOOK_EXC_TRIP
@CustomerFname VARCHAR(50),
@CustomerLname VARCHAR(50),
@CustomerDOB Date,
@BookingNumber char(7),
@CruiseshipName varchar(50),
@Trip_StartDate Date,
@Trip_EndDate Date,
@ExcursionName varchar(225),
@ExcursionTStartTime Datetime,
@ExcursionTEndTime Datetime,
@RegisterTime DateTime
AS
    DECLARE @CB_ID INT, @ET_ID INT
    EXEC getExcurTripID
    @ShipName = @CruiseshipName,
    @TripStartDate = @Trip_StartDate,
    @TripEndDate = @Trip_EndDate,
    @ExcurName = @ExcursionName,
    @ExcurTripStartTime = @ExcursionTStartTime,
    @ExcurTripEndTime = @ExcursionTEndTime,
    @ExcurTripID = @ET_ID OUTPUT

    IF @ET_ID IS NULL
    BEGIN
        PRINT '@ET_ID is null'
        RAISERROR ('@ET_ID cannot be NULL', 11 , 1)
        RETURN
    END

    EXEC getCustBookID
    @CustFname = @CustomerFname,
    @CustLname = @CustomerLname,
    @CustDOB = @CustomerDOB,
    @BookingNum = @BookingNumber,
    @CustBookID = @CB_ID OUTPUT

    IF @CB_ID IS NULL
    BEGIN
        PRINT '@CB_ID is null'
        RAISERROR ('@CB_ID cannot be NULL', 11 , 1)
        RETURN
    END

    BEGIN TRANSACTION T1
        INSERT INTO tblCUST_BOOK_EXC_TRIP(RegisTime, ExcursionTripID, CustBookingID)
        VALUES (@RegisterTime, @ET_ID, @CB_ID)

        IF @@ERROR <> 0
        BEGIN
            ROLLBACK TRANSACTION T1
        END
        ELSE
            COMMIT TRANSACTION T1
GO


/* SP 2
   Create procedure to add rows into tblROUTE_LOCATION table for arrival and departure locations,
   using nested stored procedures */

-- Find LocationID
CREATE PROCEDURE findLocationID
@LocName VARCHAR(100),
@LocID INT OUTPUT
AS
    SET @LocID = (
        SELECT LocationID FROM tblLOCATION WHERE LocationName = @LocName
    )
GO

-- Find RouteID
CREATE PROCEDURE findRouteID
@RouteName VARCHAR(100),
@RouteID INT OUTPUT
AS
    SET @RouteID = (
        SELECT RouteID
        FROM tblROUTE WHERE RouteName = @RouteName
    )
GO

--insert
CREATE PROCEDURE insertRouteLocArrDep
@RouName VARCHAR(300),
@DepLoc VARCHAR(100),
@ArrLoc VARCHAR(100)

AS
    DECLARE @RouID INT, @DepLocID INT, @ArrLocID INT
    EXEC findRouteID
    @RouteName = @RouName,
    @RouteID = @RouID OUTPUT

    IF @RouID IS NULL
        BEGIN
            PRINT 'RouteID is null, no such excursion for this trip'
            RAISERROR ('@RouID must not be null', 11, 1)
            RETURN
        END


    EXEC findLocationID
@LocName = @DepLoc,
@LocID = @DepLocID OUTPUT

    IF @DepLocID IS NULL
        BEGIN
            PRINT 'DepLocID is null, no such excursion for this trip'
            RAISERROR ('@DepLocID must not be null', 11, 1)
            RETURN
        END

    EXEC findLocationID
    @LocName = @ArrLoc,
    @LocID = @ArrLocID OUTPUT

    IF @ArrLoc IS NULL
        BEGIN
            PRINT 'ArrLoc is null, no such excursion for this trip'
            RAISERROR ('@ArrLoc must not be null', 11, 1)
            RETURN
        END

    BEGIN TRAN T1
        INSERT INTO tblROUTE_LOCATION(RouteID, RouteLocTypeID, LocationID)
        VALUES(@RouID, (SELECT RouteLocTypeID FROM tblROUTE_LOCATION_TYPE WHERE RouteLocTypeName = 'Departure'), @DepLocID)

        INSERT INTO tblROUTE_LOCATION(RouteID, RouteLocTypeID, LocationID)
        VALUES(@RouID, (SELECT RouteLocTypeID FROM tblROUTE_LOCATION_TYPE WHERE RouteLocTypeName = 'Arrival'), @ArrLocID)

        IF @@ERROR <> 0
            BEGIN
                ROLLBACK TRAN T1
            END
        ELSE
            COMMIT TRAN T1
GO


/* Synthetic Transaction
 WRAPPER sp_insertCUST_BOOK_EXC_TRIP
 */
CREATE PROCEDURE WRAPPER_insertCUST_BOOK_EXC_TRIP
@RUN INT
AS
    DECLARE @RowCount_ET INT, @RowCount_CB INT, @RandPK_ET INT, @RandPK_CB INT
    SET @RowCount_ET = (SELECT COUNT(*) FROM tblEXCURSION_TRIP)
    SET @RowCount_CB = (SELECT COUNT(*) FROM tblCUST_BOOK)

    DECLARE @C_Fname VARCHAR(50), @C_Lname VARCHAR(50), @C_DOB Date
    DECLARE @B_Number char(7), @C_Name varchar(50)
    DECLARE @T_StartDate Date, @T_EndDate Date, @E_Name varchar(225), @ET_StartTime Datetime, @ET_EndTime Datetime
    DECLARE @R_Time DateTime

    WHILE @RUN > 0
    BEGIN
        SET @RandPK_ET = (SELECT RAND() * @RowCount_ET + 1)
        SET @RandPK_CB = (SELECT RAND() * @RowCount_CB + 1)


        SET @C_Fname = (SELECT C.CustFname FROM tblCUSTOMER C
                            JOIN tblCUST_BOOK CB ON C.CustID = CB.CustID
                            JOIN tblBOOKING B ON CB.BookingID = B.BookingID
                        WHERE CB.CustBookingID = @RandPK_CB)
        SET @C_Lname = (SELECT C.CustLname FROM tblCUSTOMER C
                            JOIN tblCUST_BOOK CB ON C.CustID = CB.CustID
                            JOIN tblBOOKING B ON CB.BookingID = B.BookingID
                        WHERE CB.CustBookingID = @RandPK_CB)
        SET @C_DOB = (SELECT C.CustDOB FROM tblCUSTOMER C
                            JOIN tblCUST_BOOK CB ON C.CustID = CB.CustID
                            JOIN tblBOOKING B ON CB.BookingID = B.BookingID
                        WHERE CB.CustBookingID = @RandPK_CB)
        SET @B_Number = (SELECT B.BookingNumber FROM tblBOOKING B
                            JOIN tblCUST_BOOK CB ON B.BookingID = CB.BookingID
                        WHERE CB.CustBookingID = @RandPK_CB)
        SET @C_Name = (SELECT C.CruiseshipName FROM tblCRUISESHIP C
                            JOIN tblTRIP T ON C.CruiseshipID = T.CruiseshipID
                            JOIN tblEXCURSION_TRIP ET ON T.TripID = ET.TripID
                        WHERE ET.ExcursionTripID = @RandPK_ET)

        SET @T_StartDate = (SELECT T.StartDate FROM tblTRIP T
                                JOIN tblEXCURSION_TRIP ET on T.TripID = ET.TripID
                            WHERE ET.ExcursionTripID = @RandPK_ET)

        SET @T_EndDate = (SELECT T.EndDate FROM tblTRIP T
                                JOIN tblEXCURSION_TRIP ET on T.TripID = ET.TripID
                            WHERE ET.ExcursionTripID = @RandPK_ET)

        SET @E_Name = (SELECT E.ExcursionName FROM tblEXCURSION E
                            JOIN tblEXCURSION_TRIP ET ON E.ExcursionID = ET.ExcursionID
                       WHERE ET.ExcursionTripID = @RandPK_ET)
        SET @ET_StartTime = (SELECT ET.StartTime  FROM tblEXCURSION E
                                JOIN tblEXCURSION_TRIP ET ON E.ExcursionID = ET.ExcursionID
                            WHERE ET.ExcursionTripID = @RandPK_ET)
        SET @ET_EndTime = (SELECT ET.EndTime FROM tblEXCURSION E
                                JOIN tblEXCURSION_TRIP ET ON E.ExcursionID = ET.ExcursionID
                            WHERE ET.ExcursionTripID = @RandPK_ET)

       SET @R_Time = ((SELECT B.BookingTime FROM tblBOOKING B) + FLOOR(RAND() * 10))

        EXEC sp_insertCUST_BOOK_EXC_TRIP
        @CustomerFname = @C_Fname,
    @CustomerLname = @C_Lname,
    @CustomerDOB = @C_DOB,
    @BookingNumber = @B_Number,
    @CruiseshipName = @C_Name,
    @Trip_StartDate = @T_StartDate,
    @Trip_EndDate = @T_EndDate,
    @ExcursionName = @E_Name,
    @ExcursionTStartTime = @ET_StartTime,
    @ExcursionTEndTime = @ET_EndTime,
    @RegisterTime = @R_Time

        SET @RUN = @RUN - 1
    END





