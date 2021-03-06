\name{stabsel}
\alias{stabsel}
\title{
    Stability Selection
}
\description{
    Selection of influential variables or model components with error control.
}
\usage{
stabsel(object, FWER = 0.05, cutoff, q, 
        papply = if (require("multicore")) mclapply else lapply, ...)
}
\arguments{
  \item{object}{an \code{mboost} object.}
  \item{FWER}{family-wise error rate to be controlled by the selection procedure.}
  \item{cutoff}{cutoff between 0.5 and 1.}
  \item{q}{average number of selected variables.}
  \item{papply}{ (parallel) apply function. In the absence of package \code{multicore} sequential
    computations via \code{\link{lapply}} are performed. Alternatively,
    parallel computing via \code{\link[multicore]{mclapply}} (package \code{multicore}),
    or \code{clusterApplyLB} (package \code{snow}) can be used. In the
    latter case, usually more setup is needed (see example for some details).}
  \item{\dots}{additional arguments to \code{\link{cvrisk}}.}
}
\details{

  This function implements the "stability selection" procedure
  by Meinshausen and Buehlmann (2010).

  Either \code{cutoff} or \code{q} must be specified. The probability
  of selecting at least one non-influential variable (or model component)
  is less than \code{FWER}.

}
\value{
  An object of class \code{stabsel} with elements
  \item{phat }{selection probabilities.}
  \item{selected }{elements with maximal selection probability greater \code{cutoff}.}
  \item{max }{maximum of selection probabilities.}
  \item{cutoff }{cutoff used.}
  \item{q }{average number of selected variables used.}
  \item{FWER }{family-wise error rate.}
}
\references{

  N. Meinshausen and P. Buehlmann (2010), Stability selection.
  \emph{Journal of the Royal Statistical Society, Series B},
  \bold{72}(4).

}
\examples{


  ### (too) low-dimensional example    
  sbody <- stabsel(glmboost(DEXfat ~ ., data = bodyfat), q = 3,
                   papply = lapply)
  sbody
  opar <- par(mai = par("mai") * c(1, 1, 1, 2.7))
  plot(sbody)
  par(opar)

}
\keyword{nonparametric}
