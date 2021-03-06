
##
## cross-validation (bootstrap, k-fold cv etc.) of empirical risk 
## for boosting algorithms
##

cvrisk <- function(object, folds, 
                   grid = floor(seq(from = floor(mstop(object)/10), 
                                    to = mstop(object), length = 10))) {

    fitfct <- object$update
    oobrisk <- matrix(0, nrow = ncol(folds), ncol = length(grid))
    ctrl <- object$control
    ctrl$risk <- "oobag"

    for (i in 1:ncol(folds)) {
        model <- fitfct(object = object$data, 
                        control = ctrl, 
                        weights = folds[,i])
        oobrisk[i,] <- model$risk[grid]
    }

    oobrisk <- oobrisk / colSums(folds == 0)
    colnames(oobrisk) <- grid
    rownames(oobrisk) <- 1:nrow(oobrisk)
    attr(oobrisk, "risk") <- object$family@name
    attr(oobrisk, "call") <- deparse(object$call)
    attr(oobrisk, "mstop") <- grid
    class(oobrisk) <- "cvrisk"
    oobrisk
}

print.cvrisk <- function(x, ...) {
    cat("\n\t Cross-validated", attr(x, "risk"), "\n\t", 
              attr(x, "call"), "\n\n")
    print(colMeans(x))
    cat("\n\t Optimal number of boosting iterations:", mstop(x), "\n")
    return(invisible(x))
}

plot.cvrisk <- function(x, ylab = attr(x, "risk"), ylim = range(x), 
                        main = attr(x, "call"), ...) {

    cm <- colMeans(x)
    plot(1:ncol(x), cm, ylab = ylab, ylim = ylim, 
         type = "n", lwd = 2, axes = FALSE, 
         xlab = "Number of boosting iterations",
         main = main, ...)
    axis(1, at = 1:ncol(x), labels = colnames(x))  
    axis(2)
    box()
    out <- apply(x, 1, function(y) lines(1:ncol(x),y, col = "lightgrey"))
    rm(out)
    ms <- which.min(cm)
    lines(c(ms, ms), c(min(c(0, ylim[1] * ifelse(ylim[1] < 0, 2, 0.5))), cm[ms]), lty = 2)
    lines(1:ncol(x), cm, type = "b")
}

mstop.cvrisk <- function(object, ...)
    attr(object, "mstop")[which.min(colSums(object))]
