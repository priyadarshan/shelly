#|
  This file is a part of shelly project.
  Copyright (c) 2012-2014 Eitaro Fukamachi (e.arrows@gmail.com)
|#

(in-package :cl-user)
(defpackage shelly-test-asd
  (:use :cl :asdf))
(in-package :shelly-test-asd)

(defsystem shelly-test
  :author "Eitaro Fukamachi"
  :license "BSD"
  :depends-on (:shelly
               :cl-test-more)
  :components ((:module "t"
                :components
                ((:test-file "shelly"))))
  :defsystem-depends-on (:cl-test-more)
  :perform (test-op :after (op c)
                    (funcall (intern #. (string :run-test-system) :cl-test-more)
                             c)))
