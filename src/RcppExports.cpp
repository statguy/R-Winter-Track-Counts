// This file was generated by Rcpp::compileAttributes
// Generator token: 10BE3573-1514-4C36-9D1C-5A225CD40393

#include <Rcpp.h>

using namespace Rcpp;

// internal_countIntersections
SEXP internal_countIntersections(Rcpp::NumericMatrix track, Rcpp::NumericMatrix surveyRoute);
RcppExport SEXP STREM_internal_countIntersections(SEXP trackSEXP, SEXP surveyRouteSEXP) {
BEGIN_RCPP
    Rcpp::RObject __result;
    Rcpp::RNGScope __rngScope;
    Rcpp::traits::input_parameter< Rcpp::NumericMatrix >::type track(trackSEXP);
    Rcpp::traits::input_parameter< Rcpp::NumericMatrix >::type surveyRoute(surveyRouteSEXP);
    __result = Rcpp::wrap(internal_countIntersections(track, surveyRoute));
    return __result;
END_RCPP
}
