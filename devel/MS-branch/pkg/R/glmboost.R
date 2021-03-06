
### 
### Experimental version of gradient boosting with componentwise least
### squares as base learner, i.e., fitting of generalized linear models
### 


### Fitting function
glmboost_fit <- function(object, family = GaussReg(), control = boost_control(),
                      weights = NULL) {

    sigma <- 1
    
    ### init data and weights
    x <- object$x
    if (control$center) {
        x <- object$center(x)
        ### object$x <- x
    }
    y <- object$yfit
    check_y_family(object$y, family)
    if (is.null(weights)) {
        weights <- object$w
    } else {
        if (NROW(x) == length(weights)) 
            object$w <- weights
        else 
            stop(sQuote("weights"), " is not of length ", NROW(x))
    }

    ### hyper parameters
    mstop <- control$mstop
    risk <- control$risk
    constraint <- control$constraint
    nu <- control$nu
    trace <- control$trace
    tracestep <- options("width")$width / 2

    ### extract negative gradient and risk functions
    ngradient <- family@ngradient
    riskfct <- family@risk

    ### unweighted problem
    WONE <- (max(abs(weights - 1)) < .Machine$double.eps)
    if (!family@weights && !WONE)
        stop(sQuote("family"), " is not able to deal with weights") 

    ### rescale weights (because of the AIC criterion)
    ### <FIXME> is this correct with zero weights??? </FIXME>
    weights <- rescale_weights(weights)
    oobweights <- as.numeric(weights == 0)

    ### the ensemble
    ens <- matrix(NA, nrow = mstop, ncol = 2)
    colnames(ens) <- c("xselect", "coef")

    ### vector of empirical risks for all boosting iterations 
    ### (either in-bag or out-of-bag)
    sigmavec <- numeric(mstop)
    sigmavec[1:mstop] <- NA
    mrisk <- numeric(mstop)
    mrisk[1:mstop] <- NA

    ### some calculations independent of mstop and memory allocation
    ### for each _column_ of the design matrix x, compute the corresponding
    ### Moore-Penrose inverse (which is a scalar in this case) for the raw
    ### and standardized input variables
    xw <- t(x * weights)
    xtx <- colSums(x^2 * weights)
    sxtx <- sqrt(xtx)
    ### MPinv <- (1 / xtx) * xw
    MPinvS <- (1 / sxtx) * xw
    if (all(is.na(MPinvS)))
        warning("cannot compute column-wise inverses of design matrix")

    #browser()
    fit <- offset <- family@offset(y, weights)
    u <- ustart <- ngradient(1, y, fit, weights)
    
    #if (class(y)=="Surv") event <- y[,2]
    
    ### log likelihood evaluation function for scale parameter estimation
    logl <- function(sigma, ff){
        vec <- family@loss(y, f=ff, sigma=sigma)
        sum(vec)
        }
        
    logl2 <- function(nu, y, fit, coef, sel){
        vec <- family@loss(sigma=1, y, f = fit + (nu*coef)*sel)
        sum(vec)
        }

    ### start boosting iteration
    for (m in 1:mstop) {
  
        ### fit least squares to residuals _componentwise_, i.e.,
        ### compute regression coefficients for each _standardized_
        ### input variable and select the best variable
        xselect <- which.max(abs(mu <- MPinvS %*% u))

        ### estimate regression coefficient (not standardized)
        coef <- mu[xselect] / sxtx[xselect]
        
        #nu <- optimize(logl2, interval=c(0,100), y=y, fit=fit,
        #                  coef=coef, sel=x[,xselect])$minimum
        
        ### update step
        fit <- fit + (nu * coef) * x[,xselect]

        ### L2 boost with constraints (binary classification)
        if (constraint)
            fit <- sign(fit) * pmin(abs(fit), 1)
            
        ### scale parameter estimation for aft models
        
        if (family@sigmaTF == TRUE)
        sigma <- optimize(logl, interval=c(0,100), ff=fit)$minimum
        sigmavec[m] <- sigma
        

        ### negative gradient vector, the new `residuals'
        u <- ngradient(sigma, y, fit, weights)

        ### evaluate risk, either for the learning sample (inbag)
        ### or the test sample (oobag)
        if (risk == "inbag") mrisk[m] <- riskfct(sigma, y, fit, weights)
        if (risk == "oobag") mrisk[m] <- riskfct(sigma, y, fit, oobweights)

        ### save the model, i.e., the selected coefficient and variance
        ens[m,] <- c(xselect, coef)

        ### print status information
        if (trace) 
            do_trace(m, risk = mrisk, step = tracestep, width = mstop)
    }

    updatefun <- function(object, control, weights)
        glmboost_fit(object, family = family,
                     control = control, weights = weights)

    RET <- list(ensemble = ens,		### coefficients for selected variables
                fit = fit,		### vector of fitted values
                sigma = sigmavec, ### scale parameter estimate
                offset = offset,	### offset
                ustart = ustart,	### first negative gradients
                risk = mrisk,		### empirical risks for m = 1, ..., mstop
                control = control, 	### control parameters
                family = family,	### family object
                response = y, 		### the response variable
                weights = weights,	### weights used for fitting
                update = updatefun,	### a function for fitting with new weights
                MPinv = MPinvS / sxtx,	### Moore-Penrose inverse of x
                nu = nu
    )

    ### save learning sample
    if (control$savedata) RET$data <- object
    class(RET) <- c("glmboost", "gb")

    ### prediction function (linear predictor only)
    RET$predict <- function(newdata = NULL, mstop = mstop, ...) {

        if (!is.null(newdata)) {
            if (is.null(object$menv)) {
                if (!is.matrix(newdata) || ncol(newdata) != ncol(x))
                    stop(sQuote("newdata"), " is not a matrix with ",
                         ncol(x), " columns")
                x <- newdata
            } else {
                mf <- object$menv@get("input", data = newdata)
                x <- model.matrix(attr(mf, "terms"), data = mf)
            }
            if (control$center) x <- object$center(x)
        }

        tmp <- RET
        tmp$ensemble <- tmp$ensemble[1:mstop,,drop = FALSE]
        lp <- offset + x %*% coef(tmp)
        if (constraint) lp <- sign(lp) * pmin(abs(lp), 1)    
        return(drop(lp))
    }
    ### function for computing hat matrices of individual predictors
    RET$hat <- function(j) x[,j] %*% RET$MPinv[j, ,drop = FALSE]

    return(RET)
}


### Fitting function
glmboost2_fit <- function(object, family = GaussReg(), control = boost_control(),
                      weights = NULL) {

    sigma <- 1
    
    ### init data and weights
    x <- object$x
    if (control$center) {
        x <- object$center(x)
        ### object$x <- x
    }
    y <- object$yfit
    check_y_family(object$y, family)
    if (is.null(weights)) {
        weights <- object$w
    } else {
        if (NROW(x) == length(weights)) 
            object$w <- weights
        else 
            stop(sQuote("weights"), " is not of length ", NROW(x))
    }

    ### hyper parameters
    mstop <- control$mstop
    risk <- control$risk
    constraint <- control$constraint
    nu <- control$nu
    trace <- control$trace
    tracestep <- options("width")$width / 2

    ### extract negative gradient and risk functions
    ngradient <- family@ngradient
    riskfct <- family@risk

    ### unweighted problem
    WONE <- (max(abs(weights - 1)) < .Machine$double.eps)
    if (!family@weights && !WONE)
        stop(sQuote("family"), " is not able to deal with weights") 

    ### rescale weights (because of the AIC criterion)
    ### <FIXME> is this correct with zero weights??? </FIXME>
    weights <- rescale_weights(weights)
    oobweights <- as.numeric(weights == 0)

    ### the ensemble
    ens <- matrix(NA, nrow = mstop, ncol = 2)
    colnames(ens) <- c("xselect", "coef")

    ### vector of empirical risks for all boosting iterations 
    ### (either in-bag or out-of-bag)
    sigmavec <- numeric(mstop)
    sigmavec[1:mstop] <- NA
    mrisk <- numeric(mstop)
    mrisk[1:mstop] <- NA

    ### some calculations independent of mstop and memory allocation
    ### for each _column_ of the design matrix x, compute the corresponding
    ### Moore-Penrose inverse (which is a scalar in this case) for the raw
    ### and standardized input variables
    xw <- t(x * weights)
    xtx <- colSums(x^2 * weights)
    sxtx <- sqrt(xtx)
    ### MPinv <- (1 / xtx) * xw
    MPinvS <- (1 / sxtx) * xw
    if (all(is.na(MPinvS)))
        warning("cannot compute column-wise inverses of design matrix")

    #browser()
    fit <- offset <- family@offset(y, weights)
    u <- ustart <- ngradient(1, y, fit, weights)
    
    #if (class(y)=="Surv") event <- y[,2]
    
    ### log likelihood evaluation function for scale parameter estimation
    logl <- function(sigma, ff){
        vec <- family@loss(y, f=ff, sigma=sigma)
        sum(vec)
        }
        

    ### start boosting iteration
    for (m in 1:mstop) {
        
        logl2 <- function(nu){
        vec <- family@loss(sigma=1, y, f = fit + (nu * coef) * x[,xselect])
        sum(vec)
        }
        
        ### fit least squares to residuals _componentwise_, i.e.,
        ### compute regression coefficients for each _standardized_
        ### input variable and select the best variable
        xselect <- which.max(abs(mu <- MPinvS %*% u))

        ### estimate regression coefficient (not standardized)
        coef <- mu[xselect] / sxtx[xselect]
        
        #nu <- nlm(logl2, p=0.5)$estimate

        ### update step
        fit <- pmin(fit + (nu * coef) * x[,xselect], 15)
        fit <- pmax(fit, -15)

        ### L2 boost with constraints (binary classification)
        if (family@name == "Zero-inflated NegBin Likelihood, theta part")
            fit <- pmax(fit, 10e-3)
            
        ### scale parameter estimation for aft models
        
        if (family@sigmaTF == TRUE)
        sigma <- optimize(logl)$minimum
        sigmavec[m] <- sigma
        

        ### negative gradient vector, the new `residuals'
        u <- ngradient(sigma, y, fit, weights)

        ### evaluate risk, either for the learning sample (inbag)
        ### or the test sample (oobag)
        if (risk == "inbag") mrisk[m] <- riskfct(sigma, y, fit, weights)
        if (risk == "oobag") mrisk[m] <- riskfct(sigma, y, fit, oobweights)

        ### save the model, i.e., the selected coefficient and variance
        ens[m,] <- c(xselect, coef)

        ### print status information
        if (trace) 
            do_trace(m, risk = mrisk, step = tracestep, width = mstop)
    }

    updatefun <- function(object, control, weights)
        glmboost_fit(object, family = family,
                     control = control, weights = weights)

    RET <- list(ensemble = ens,		### coefficients for selected variables
                fit = fit,		### vector of fitted values
                sigma = sigmavec, ### scale parameter estimate
                offset = offset,	### offset
                ustart = ustart,	### first negative gradients
                risk = mrisk,		### empirical risks for m = 1, ..., mstop
                control = control, 	### control parameters
                family = family,	### family object
                response = y, 		### the response variable
                weights = weights,	### weights used for fitting
                update = updatefun,	### a function for fitting with new weights
                MPinv = MPinvS / sxtx,	### Moore-Penrose inverse of x
                nu = nu
    )

    ### save learning sample
    if (control$savedata) RET$data <- object
    class(RET) <- c("glmboost", "gb")

    ### prediction function (linear predictor only)
    RET$predict <- function(newdata = NULL, mstop = mstop, ...) {

        if (!is.null(newdata)) {
            if (is.null(object$menv)) {
                if (!is.matrix(newdata) || ncol(newdata) != ncol(x))
                    stop(sQuote("newdata"), " is not a matrix with ",
                         ncol(x), " columns")
                x <- newdata
            } else {
                mf <- object$menv@get("input", data = newdata)
                x <- model.matrix(attr(mf, "terms"), data = mf)
            }
            if (control$center) x <- object$center(x)
        }

        tmp <- RET
        tmp$ensemble <- tmp$ensemble[1:mstop,,drop = FALSE]
        lp <- offset + x %*% coef(tmp)
        if (constraint) lp <- sign(lp) * pmin(abs(lp), 1)    
        return(drop(lp))
    }
    ### function for computing hat matrices of individual predictors
    RET$hat <- function(j) x[,j] %*% RET$MPinv[j, ,drop = FALSE]

    return(RET)
}


### generic method for gradient boosting with componentwise linear models
### for fitting generalized linear models
glmboost <- function(x, ...) UseMethod("glmboost")
glmboost2 <- function(x, ...) UseMethod("glmboost2")

### formula interface
glmboost.formula <- function(formula, data = list(), weights = NULL, 
                             contrasts.arg = NULL, na.action = na.pass, ...) {

    ### control and contrasts.arg might be confused here
    if (!is.null(contrasts.arg)) {
        if (extends(class(contrasts.arg), "boost_control"))
            stop(sQuote("contrasts.arg"), " is not a list of contrasts")
    }

    ### construct design matrix etc.
    object <- boost_dpp(formula, data, weights, contrasts.arg = contrasts.arg, 
                        na.action = na.action)

    object$center <- function(xmat) {
        cm <- colMeans(object$x)
        num <- which(sapply(object$menv@get("input"), class) == "numeric")
        cm[!attr(object$x, "assign") %in% num] <- 0       
        scale(xmat, center = cm, scale = FALSE)
    }

    ### fit the ensemble
    RET <- glmboost_fit(object, ...)

    RET$call <- match.call()

    return(RET)
}


glmboost2.formula <- function(formula, data = list(), weights = NULL, 
                             contrasts.arg = NULL, na.action = na.pass, ...) {

    ### control and contrasts.arg might be confused here
    if (!is.null(contrasts.arg)) {
        if (extends(class(contrasts.arg), "boost_control"))
            stop(sQuote("contrasts.arg"), " is not a list of contrasts")
    }

    ### construct design matrix etc.
    object <- boost_dpp(formula, data, weights, contrasts.arg = contrasts.arg, 
                        na.action = na.action)

    object$center <- function(xmat) {
        cm <- colMeans(object$x)
        num <- which(sapply(object$menv@get("input"), class) == "numeric")
        cm[!attr(object$x, "assign") %in% num] <- 0       
        scale(xmat, center = cm, scale = FALSE)
    }

    ### fit the ensemble
    RET <- glmboost2_fit(object, ...)

    RET$call <- match.call()

    return(RET)
}

### matrix interface
glmboost.matrix <- function(x, y, weights = NULL, ...) {

    if (NROW(x) != NROW(y))
        stop("number of observations in", sQuote("x"), "and", 
             sQuote("y"), "differ")
    if (is.null(weights)) weights <- rep(1, NROW(x))
    if (length(weights) != NROW(x))
        stop("number of observations in", sQuote("x"), "and", 
             sQuote("weights"), "differ")

    object <- gb_xyw(x, y, weights)
    object$center <- function(xmat) 
        scale(xmat, center = colMeans(x), scale = FALSE)
    RET <- glmboost_fit(object, ...)
    RET$call <- match.call()
    return(RET)
}

glmboost2.matrix <- function(x, y, weights = NULL, ...) {

    if (NROW(x) != NROW(y))
        stop("number of observations in", sQuote("x"), "and", 
             sQuote("y"), "differ")
    if (is.null(weights)) weights <- rep(1, NROW(x))
    if (length(weights) != NROW(x))
        stop("number of observations in", sQuote("x"), "and", 
             sQuote("weights"), "differ")

    object <- gb_xyw(x, y, weights)
    object$center <- function(xmat) 
        scale(xmat, center = colMeans(x), scale = FALSE)
    RET <- glmboost2_fit(object, ...)
    RET$call <- match.call()
    return(RET)
}

### methods: coefficients
coef.glmboost <- function(object, ...) {

    ret <- numeric(NCOL(object$data$x))
    xselect <- object$ensemble[,"xselect"]
    for (j in unique(xselect))
        ret[j] <- sum(object$ensemble[xselect == j, "coef"])
    names(ret) <- colnames(object$data$x)
    RET <- ret * object$control$nu
    attr(RET, "offset") <- object$offset
    RET
}

### coef path
coefpath <- function(object, ...) UseMethod("coefpath")
coefpath.glmboost <- function(object, ...) {

    vars <- colnames(object$data$x)
    xselect <- object$ensemble[,"xselect"]
    svars <- vars[tabulate(xselect, nbins = length(vars)) > 0]
    ret <- matrix(0, nrow = mstop(object), ncol = length(svars))
    colnames(ret) <- svars
    for (j in unique(xselect)) {
        indx <- which(xselect == j)
        ret[indx, svars[svars == vars[j]]] <- 
            object$ensemble[indx, "coef"]
    }
    RET <- ret * object$control$nu
    apply(RET, 2, cumsum)
}

### methods: hatvalues. 
hatvalues.glmboost <- function(model, ...) {

    if (!checkL2(model)) return(hatglm(model))
    xf <- t(model$MPinv) * model$control$nu
    x <- model$data$x
    if (model$control$center) x <- model$data$center(x)
    op <- .Call("R_trace_glmboost", x, xf,
                as.integer(model$ensemble[, "xselect"]),
                PACKAGE = "mboost")
    RET <- diag(op[[1]])
    attr(RET, "hatmatrix") <- op[[1]]  
    attr(RET, "trace") <- op[[2]] 
    RET
}

### methods: print
print.glmboost <- function(x, ...) {

    cat("\n")
    cat("\t Generalized Linear Models Fitted via Gradient Boosting\n")
    cat("\n")
    if (!is.null(x$call))
    cat("Call:\n", deparse(x$call), "\n\n", sep = "")
    show(x$family)
    cat("\n")
    cat("Number of boosting iterations: mstop =", mstop(x), "\n")
    cat("Step size: ", x$control$nu, "\n")
    cat("Offset: ", x$offset, "\n")
    cat("\n")
    cat("Coefficients: \n")
    #cf <- coef(x)
    attr(x, "offset") <- NULL
    #print(cf)
    cat("\n")
    invisible(x)
}

plot.glmboost <- function(x, main = deparse(x$call), 
                          col = NULL, ...) {

    cp <- coefpath(x)
    cp <- cp[,order(cp[nrow(cp),])]
    cf <- cp[nrow(cp),]
    if (is.null(col))
        col <- hcl(h = 40, l = 50, c= abs(cf) / max(abs(cf)) * 490)
    matplot(cp, type = "l", lty = 1, xlab = "Number of boosting iterations", 
            ylab = "Coefficients", main = main, col = col, ...)
    abline(h = 0, lty = 1, col = "lightgray")
    axis(4, at = cp[nrow(cp),], labels = colnames(cp), 
         las = 1)
    
}
