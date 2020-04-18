pragma solidity ^0.5.0;

import "./LoanRequestHub.sol";

contract  Loan{
    //Contract Term Variables
    address Lender;
    address Borrower;
    uint TimeToAccept;
    uint Principal;
    uint InterestRate; // annual interest rate in percent NOT USED FOR CALCULATIONS
    uint TotalInterestDue;
    uint TotalDueByEnd;
    uint TermLength; //Payment terms in days        
    uint PaymentIntervals;
    uint MinPayment;        

    //variables calculated in contract
    
    uint DateToAccept;
    uint RemainingBalance;
    uint TermLengthRemaining;
    uint LastPaymentReceived;
    uint TotalPaymentsReceived;
    uint PendingPayment;
    uint NextDueDate;
    uint StartDate;
    uint EndDate;
    
    uint HoldTermLength;
    
    //Stages of the contract
    enum Stage {
            AwaitingBorrowerDecision,
            WaitingforFunds,
            WaitingforPayment,
            WaitingforRemediation,
            End
        }
    
    //Restricts function usability to certain stages
    modifier onlyStage (Stage _stage) {
    require(currentStage == _stage, "The prior stage must be completed");
    _;
    }
    
    //Restricts function usability to Lender only
    modifier onlyLender(address _who) {
    require(Lender == _who, "You do not have permission to access this");
    _;
    }
    
    //Restricts function usability to Borrower only
    modifier onlyBorrower(address _who) {
    require(Borrower == _who, "You do not have permission to access this");
    _;
    }
    
    //initializes all Contract Term Variables passed from the factory contract
    constructor (address payable _lenderadress, address payable _borroweraddress, 
    uint _timetoaccept, uint _approvedloanamount, uint _interestrate, uint _totalinterestdue, uint _termlength, uint _paymentintervals,  uint _minpayment) public {     
        Lender = _lenderadress;
        Borrower = _borroweraddress;
        TimeToAccept = _timetoaccept;
        Principal = _approvedloanamount;
        InterestRate = _interestrate;
        TotalInterestDue = _totalinterestdue;
        TermLength = _termlength;
        HoldTermLength = TermLength;
        PaymentIntervals = _paymentintervals;
        MinPayment = _minpayment;
        
        //Calculated constructor variables
        TotalDueByEnd = Principal + TotalInterestDue;
        DateToAccept = now + TimeToAccept * 1 days;
        
    }

    Stage private currentStage = Stage.AwaitingBorrowerDecision;
    
    //Function allows any user to see the terms of the loan contract
    //Returns all contract term variables
    function GetTheTerms() public view returns(address, address, uint, uint, uint, uint, uint, uint, uint, uint) {
        require(now <= DateToAccept);
        return(Lender, Borrower, TimeToAccept, Principal, InterestRate, TotalInterestDue, TotalDueByEnd, TermLength, PaymentIntervals, MinPayment);
        //inserttimetoacceptfunction
    }
    
    function GetStage() public view returns (uint) {
        return uint(currentStage);
            /*if (currentStage = Stage.AwaitingBorrowerDecision) return "AwaitingBorrowerDecision";
            if (currentStage = Stage.WaitingforFunds) return "WaitingforFunds";
            if (currentStage = Stage.WaitingforPayment) return "WaitingforPayment";
            if (currentStage = Stage.WaitingforRemediation) return "WaitingforRemediation";
            if (currentStage = Stage.End) return "Loan Ended";*/
    }
    
    //Only the borrower can accept the loan
    //Initializes time based variables
    function BorrowerAcceptTerms() public onlyBorrower(msg.sender) onlyStage(Stage.AwaitingBorrowerDecision) {
        StartDate = now;
        EndDate = now + TermLength * 1 days;        
        NextDueDate = StartDate + PaymentIntervals;
        currentStage = Stage.WaitingforFunds;
        
        if(address(this).balance > 0) {
        currentStage = Stage.WaitingforPayment;
        } else {
            currentStage = Stage.WaitingforFunds;
        }
    }
    
    function SendLoan() payable public onlyLender(msg.sender) onlyStage(Stage.WaitingforFunds) {
        Principal = msg.value;
        RemainingBalance = msg.value;
        TermLengthRemaining = TermLength;
        StartDate = now; // Loan term starts
        EndDate = now + TermLength * 1 days; //End date of loan set
        NextDueDate = now + PaymentIntervals * 1 days; //Sets next payment due date by one payment interval
    }
    
    //Reject the loan terms
    //Can only be called by loaner or borrower
    function RejectLoanTerms() public onlyBorrower(msg.sender){ 
        require(currentStage != Stage.End || currentStage != Stage.WaitingforPayment);// can occur ONLY BEFORE payment period begins (after the borrower accepts the loan)
        currentStage = Stage.End;
        //Add Reject Event
        selfdestruct(Lender);
    }
    
    function GetBalance() public view returns(uint, uint, uint, uint, uint, uint) {
        return(MinPayment, 
        RemainingBalance, 
        TermLengthRemaining, 
        PaymentIntervals, 
        RemainingBalance, 
        TotalPaymentsReceived);
    }

    //function can only be called if the borrower requests remediation
    function updateLoanTerms(uint _updatetotalduebyend, uint _updateinterestrate, uint _updatetotalinterestdue, uint _extendtermlength, uint _updatepaymentintervals,  uint _updateminpayment) 
    public onlyLender(msg.sender) onlyStage(Stage.WaitingforRemediation){
        require (_updatetotalduebyend >= _updateminpayment);
        InterestRate = _updateinterestrate; //NOT USED FOR CALCULATIONS
        TotalInterestDue = _updatetotalinterestdue ; //LENDER MUST DO THE END CALCULATIONS
        TotalDueByEnd = _updatetotalduebyend;
        RemainingBalance = TotalDueByEnd - TotalPaymentsReceived; //LENDER MUST DO THE END CALCULATIONS
        TermLength = _extendtermlength; //requires calculation from lender (in days)
        TermLengthRemaining = (StartDate + TermLength - now);
        EndDate = StartDate + TermLength;
        PaymentIntervals = _updatepaymentintervals;
        MinPayment = _updateminpayment; //LENDER MUST DO THE END CALCULATIONS
            
        //loanStatus = "Terms updated, awaiting payment.";
        currentStage = Stage.WaitingforPayment;
    }

    function payLoan() public payable { // THERE ARE NO RESTRICTIONS ON WHO CAN PAY THE LOAN. ANYONE CAN PAY THE LOAN
        require(msg.value >= MinPayment && RemainingBalance > 0); //the payment made must be greater than or equal to the monthly repayment amount
        //the payment made must be less than or equal to the remaining balance so that the lender is not overpaid
        //require(NextDueDate - now <= PaymentIntervals * 1 days); //the payment must be made within 30 days of the next due date
        LastPaymentReceived = now; //the time of the last payment received is logged

        if (RemainingBalance - msg.value >= MinPayment) { //if the total time remaining is greater than the next due dat
            NextDueDate += PaymentIntervals * 1 days; //increment next due date by payment interval
            RemainingBalance -= msg.value; //the payment received is subtracted from the remaining balance and updated
            TotalPaymentsReceived += msg.value;
        } else if (RemainingBalance - msg.value < MinPayment) { //if the total time remaining is less than the next due date
            NextDueDate = EndDate; //change the next due date to the end date
            RemainingBalance -= msg.value;
            MinPayment = RemainingBalance; //the minimum payment is changed to the remaining balance
            TotalPaymentsReceived += msg.value;
        } else if (msg.value == RemainingBalance) {
            RemainingBalance = 0;
            currentStage = Stage.End;
            selfdestruct(Lender);
        }
        //NEED TO ADD CONTRACT KILL WHEN LOAN IS FULLY PAID
    }   

    
    /*function payLoan() public payable onlyStage(Stage.WaitingforPayment) { // THERE ARE NO RESTRICTIONS ON WHO CAN PAY THE LOAN. ANYONE CAN PAY THE LOAN
        require(msg.value >= MinPayment && msg.value <= RemainingBalance && RemainingBalance > 0); //the payment made must be greater than or equal to the monthly repayment amount
        //the payment made must be less than or equal to the remaining balance so that the lender is not overpaid
        require(NextDueDate - now <= PaymentIntervals * 1 days); //the payment must be made within 30 days of the next due date
        LastPaymentReceived = now; //the time of the last payment received is logged

        if (EndDate >= NextDueDate && RemainingBalance - msg.value >= MinPayment) { //if the total time remaining is greater than the next due dat
            NextDueDate += PaymentIntervals * 1 days; //increment next due date by payment interval
            RemainingBalance -= msg.value; //the payment received is subtracted from the remaining balance and updated
            TotalPaymentsReceived += msg.value;
        } else if (EndDate < NextDueDate || RemainingBalance - msg.value < MinPayment) { //if the total time remaining is less than the next due date
            NextDueDate = EndDate; //change the next due date to the end date
            MinPayment = RemainingBalance; //the minimum payment is changed to the remaining balance
            TotalPaymentsReceived += msg.value;
        }
        //NEED TO ADD CONTRACT KILL WHEN LOAN IS FULLY PAID
    }*/ //True payment function. Not used for demo or testing    

    function requestRemediation() public onlyBorrower(msg.sender) onlyStage(Stage.WaitingforPayment) {
        //require(now >= NextDueDate);
        currentStage = Stage.WaitingforRemediation;
        //need to emit event
    }
    
    function withdraw() payable public{
        if (currentStage == Stage.WaitingforFunds && address(this).balance > 0) {
            require(msg.sender == Borrower, "Only borrower can withdraw the loan");
            Borrower.transfer(address(this).balance);
            currentStage = Stage.WaitingforPayment;
        } else if (currentStage == Stage.WaitingforPayment && address(this).balance > 0) {
            require(msg.sender == Lender, "Only the lender can withdraw the payments");
            Lender.transfer(address(this).balance);
        } else if (RemainingBalance == 0) {
            currentStage = Stage.End;
            selfdestruct(Lender);
        }
    }
}
