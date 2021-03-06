(in-package :cl-user)
(defpackage shelly.impl
  (:use :cl)
  (:export :*current-lisp-name*
           :*current-lisp-path*
           :command-line-args
           :*eval-option*
           :save-core-image
           :save-app
           :condition-undefined-function-name))
(in-package :shelly.impl)

(defvar *current-lisp-name*
    (or
     #+ccl "ccl"
     #+sbcl "sbcl"
     #+allegro "alisp"
     #+clisp "clisp"
     #+cmu "cmucl"
     #+ecl "ecl"
     #+abcl "abcl"))

(defvar *current-lisp-path*
    (or
     #+ccl (car ccl:*command-line-argument-list*)
     #+sbcl (car sb-ext:*posix-argv*)
     #+allegro (car (system:command-line-arguments))
     #+clisp "clisp"
     #+cmu (car ext:*command-line-strings*)
     #+ecl (car (si:command-args))))

(defun command-line-args ()
  (or
   #+ccl ccl:*command-line-argument-list*
   #+sbcl sb-ext:*posix-argv*
   #+allegro (system:command-line-arguments)
   #+clisp (cons "clisp" ext:*args*)
   #+cmu ext:*command-line-strings*
   #+ecl (si:command-args)))

(defvar *eval-option*
    (or
     #+ccl "--eval"
     #+sbcl "--eval"
     #+allegro "-e"
     #+clisp "-x"
     #+cmu "-eval"
     #+ecl "-eval"))

(defun save-core-image (filepath)
  (declare (ignorable filepath))
  #+allegro (progn (excl:dumplisp :name filepath) (excl:exit 1 :quiet t))
  #+ccl (ccl:save-application filepath)
  #+sbcl (sb-ext:save-lisp-and-die filepath)
  #+clisp (progn (ext:saveinitmem filepath) (ext:quit))
  #+cmu (ext:save-lisp filepath :load-init-file nil)
  #-(or allegro ccl sbcl clisp cmu)
  (error "Dumping core image isn't supported on this implementation."))

(defun save-app (filepath toplevel)
  #+sbcl
  (sb-ext:save-lisp-and-die filepath
                            :toplevel toplevel
                            :save-runtime-options t
                            :executable t)
  #+ccl
  (ccl:save-application filepath
                        :prepend-kernel t
                        :toplevel-function toplevel
                        :purify t
                        :application-class 'ccl::application
                        :error-handler :quit)
  #+clisp
  (ext:saveinitmem filepath
                   :quiet t
                   :init-function (lambda () (funcall toplevel) (ext:exit))
                   :executable t
                   :norc t)
  #-(or sbcl ccl clisp)
  (error "Making an executable isn't supported on this implementation."))

(defun condition-undefined-function-name (condition)
  (declare (ignorable condition))
  (or
   #+sbcl (slot-value condition 'sb-kernel::name)
   #+ecl (slot-value condition 'si::name)
   #+cmu (getf (conditions::condition-actual-initargs condition) :name)
   #+allegro (slot-value condition 'excl::name)
   #+ccl (slot-value condition 'ccl::name)
   #+clisp (slot-value condition 'system::$name)))
