(check-expect
  (apply + '(1 2 3 4 5 6 7 8 9 10)) 55)

(check-expect
  (map + '(1 2 3) '(1 2 3) '(1 2 3) '(1 2 3) '(1 2 3))
  '(5 10 15))
