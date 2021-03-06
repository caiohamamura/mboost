
stabsel <- function(object, FWER = 0.05, cutoff, q, 
                    papply = if (require("multicore")) mclapply else lapply, ...) {

    p <- length(variable.names(object))
    ibase <- 1:p

    stopifnot(FWER > 0 && FWER < 0.5)
    stopifnot(xor(missing(cutoff), missing(q)))
    if (missing(cutoff)) cutoff <- min(0.9, (q^2 / (FWER * p) + 1) / 2)
    if (missing(q)){
		stopifnot(cutoff >= 0.5)
		q <- ceiling(sqrt(FWER * (2 * cutoff - 1) * p))
	} 

    fun <- function(model) {
        xs <- selected(model)
        qq <- sapply(1:length(xs), function(x) length(unique(xs[1:x])))
        xs[qq > q] <- xs[1]
        xs
    }
    ss <- cvrisk(object, fun  = fun, 
                 folds = cv(model.weights(object), type = "subsampling", ...),
                 papply = papply)
    ret <- matrix(0, nrow = length(ibase), ncol = m <- mstop(object))
    for (i in 1:length(ss)) {
        tmp <- sapply(ibase, function(x) 
            ifelse(x %in% ss[[i]], which(ss[[i]] == x)[1], m + 1))
        ret <- ret + t(sapply(tmp, function(x) c(rep(0, x - 1), rep(1, m - x + 1))))
    }

    phat <- ret / length(ss)
    rownames(phat) <- names(variable.names(object))
    if (extends(class(object), "glmboost"))
        rownames(phat) <- variable.names(object)
    ret <- list(phat = phat, selected = which((mm <- apply(phat, 1, max)) >= cutoff),
                max = mm, cutoff = cutoff, q = q)
    class(ret) <- "stabsel"
    ret
}

print.stabsel <- function(x, ...) {

    cat("\tStability Selection\n")
    if (length(x$selected) > 0) {
        cat("\nSelected base-learners:\n")
        print(x$selected)
    } else {
        cat("\nNo base-learner selected\n")
    }
    cat("\nSelection probabilities:\n")
    print(x$max[x$max > 0])
    cat("\nCutoff: ", x$cutoff, "; ", sep = "")
    cat("q: ", x$q, "\n\n")
    invisible(x)
}

plot.stabsel <- function(x, main = deparse(x$call), col = NULL, ...) {

    h <- x$phat
    h <- h[rowSums(h) > 0, , drop = FALSE]
    if (is.null(col))
        col <- hcl(h = 40, l = 50, c = h[,ncol(h)] / max(h) * 490)
    matplot(t(h), type = "l", lty = 1, xlab = "Number of boosting iterations",
            ylab = "Selection Probability", main = main, col = col, ylim = c(0, 1), ...)
    abline(h = x$cutoff, lty = 1, col = "lightgray")
    axis(4, at = x$phat[rowSums(x$phat) > 0, ncol(x$phat)], 
         labels = rownames(x$phat)[rowSums(x$phat) > 0], las = 1)
}

    
fitsel <- function(object, newdata = NULL, which = NULL, ...) {
    fun <- function(model) {
        tmp <- predict(model, newdata = newdata, 
                       which = which, agg = "cumsum")
        ret <- c()
        for (i in 1:length(tmp))
            ret <- rbind(ret, tmp[[i]])
        ret
    }
    ss <- cvrisk(object, fun = fun, ...)
    ret <- matrix(0, nrow = nrow(ss[[1]]), ncol = ncol(ss[[1]]))
    for (i in 1:length(ss))
        ret <- ret + sign(ss[[i]])
    ret <- abs(ret) / length(ss)
    ret
}
