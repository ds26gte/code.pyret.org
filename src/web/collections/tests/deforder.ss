(provide f1 f2 x foo)

(define (f1)
  (+ x 1))

(define x 2)

(define (f2)
  (make-foo))

(define-struct foo ())

(check-expect (f1) 3)
