context("functions")

# some helpers
if (py_available()) {
  inspect <- import("inspect")
  test <- import("rpytools.test")
}

test_that("Python functions are marshalled as function objects", {
  skip_if_no_python()
  spec <- inspect$getargspec(inspect$getclasstree)
  expect_equal(spec$args, c("classes", "unique"))
})

test_that("Python functions can be called by python", {
  skip_if_no_python()
  x <- "foo"
  expect_equal(test$callFunc(test$asString, x), x)
})

