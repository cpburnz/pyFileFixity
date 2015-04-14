# Copyright (c) 2010 Andrew Brown <brownan@cs.duke.edu, brownan@gmail.com>
# Copyright (c) 2015 Stephen Larroque <LRQ3000@gmail.com>
# See LICENSE.txt for license terms

import cython
cimport cython

from cStringIO import StringIO
from itertools import izip

@cython.freelist(64) # fast instanciation via freelist pool
@cython.nonecheck(False) # Turn off nonecheck locally for the function
@cython.boundscheck(False) # turn off boundscheck for this function
cdef class Polynomial:
    """Completely general polynomial class.

    Polynomial objects are immutable.

    Implementation note: while this class is mostly agnostic to the type of
    coefficients used (as long as they support the usual mathematical
    operations), the Polynomial class still assumes the additive identity and
    multiplicative identity are 0 and 1 respectively. If you're doing math over
    some strange field or using non-numbers as coefficients, this class will
    need to be modified."""

    cdef public list coefficients
    cdef public int degree

    def __cinit__(self, list coefficients=None, **sparse):
        """
        There are three ways to initialize a Polynomial object.
        1) With a list, tuple, or other iterable, creates a polynomial using
        the items as coefficients in order of decreasing power

        2) With keyword arguments such as for example x3=5, sets the
        coefficient of x^3 to be 5

        3) With no arguments, creates an empty polynomial, equivalent to
        Polynomial((0,))

        >>> print Polynomial((5, 0, 0, 0, 0, 0))
        5x^5

        >>> print Polynomial(x32=5, x64=8)
        8x^64 + 5x^32

        >>> print Polynomial(x5=5, x9=4, x0=2) 
        4x^9 + 5x^5 + 2
        """
        if coefficients and sparse:
            raise TypeError("Specify coefficients list /or/ keyword terms, not"
                    " both")
        if coefficients:
            # Polynomial( [1, 2, 3, ...] )
            #c = coefficients
            #if isinstance(coefficients, tuple): c = list(coefficients)
            # Expunge any leading 0 coefficients
            while coefficients and coefficients[0] == 0:
                coefficients.pop(0)
            if not coefficients:
                coefficients.append(0)

            self.coefficients = coefficients
        elif sparse:
            # Polynomial(x32=...)
            powers = sparse.keys()
            powers.sort(reverse=1)
            # Not catching possible exceptions from the following line, let
            # them bubble up.
            highest = int(powers[0][1:])
            coefficients = [0] * (highest+1)

            for power, coeff in sparse.iteritems():
                power = int(power[1:])
                coefficients[highest - power] = coeff

            self.coefficients = coefficients
        else:
            # Polynomial()
            self.coefficients = [0]
        self.degree = len(self.coefficients)

    def __len__(self):
        """Returns the number of terms in the polynomial"""
        return self.degree

#    cdef degree(self, Polynomial poly=None):
#        """Returns the degree of the polynomial"""
#        if not poly:
#            return len(self.coefficients) - 1
#        elif poly and hasattr("coefficients", poly):
#            return len(poly.coefficients) - 1
#        else:
#            while poly and poly[-1] == 0:
#                poly.pop()   # normalize
#            return len(poly)-1

    def __add__(self, Polynomial other):
        cdef int diff = self.degree - other.degree
        # if diff > 0:
            # t1 = self.coefficients
            # t2 = (0,) * diff + other.coefficients
        # else:
            # t1 = (0,) * (-diff) + self.coefficients
            # t2 = other.coefficients
        cdef list t1 = [0] * (-diff) + self.coefficients
        cdef list t2 = [0] * diff + other.coefficients

        return self.__class__([x+y for x,y in izip(t1, t2)])

    def __neg__(self):
        cdef list c = []
        for x in self.coefficients:
            c.append(-x)
        return self.__class__(c)
    def __sub__(self, Polynomial other):
        return self + -other

    def __mul__(self, Polynomial other):
        cdef list terms = [0] * (self.degree + other.degree)

        cdef int l1 = self.degree-1
        cdef int l2 = other.degree-1
        for i1, c1 in enumerate(self.coefficients):
            if c1 == 0:
                # Optimization
                continue
            for i2, c2 in enumerate(other.coefficients):
                if c2 == 0:
                    continue
                else:
                    terms[-((l1-i1)+(l2-i2))-1] += c1*c2
        return self.__class__(terms)

    def __floordiv__(self, Polynomial other):
        return divmod(self, other)[0]
    def __mod__(self, Polynomial other):
        return divmod(self, other)[1]

    def __divmod__(Polynomial dividend, Polynomial divisor):
        '''Implementation of the Polynomial Long Division, without recursion. Polynomial Long Division is very similar to a simple division of integers, see purplemath.com. Implementation inspired by the pseudo-code from Rosettacode.org'''
        '''Pseudocode:
        degree(P):
          return the index of the last non-zero element of P;
                 if all elements are 0, return -inf

        polynomial_long_division(N, D) returns (q, r):
          // N, D, q, r are vectors
          if degree(D) < 0 then error
          if degree(N) >= degree(D) then
            q = 0
            while degree(N) >= degree(D)
              d = D shifted right by (degree(N) - degree(D))
              q[degree(N) - degree(D)] = N(degree(N)) / d(degree(d))
              // by construction, degree(d) = degree(N) of course
              d = d * q[degree(N) - degree(D)]
              N = N - d
            endwhile
            r = N
          else
            q = 0
            r = N
          endif
          return (q, r)
          '''
        class_ = dividend.__class__

        # See how many times the highest order term
        # of the divisor can go into the highest order term of the dividend

        cdef int dividend_power = dividend.degree
        cdef int dividend_coefficient = dividend[0]

        cdef int divisor_power = divisor.degree
        cdef int divisor_coefficient = divisor[0]
        
        cdef int remainder_power
        cdef int remainder_coefficient
        cdef int quotient_power
        cdef int quontient_coefficient
        cdef Polynomial remainder
        cdef Polynomial quotient
        cdef Polynomial q

        if divisor_power < 0:
            raise ZeroDivisionError
        elif dividend_power < divisor_power:
            # Doesn't divide at all, return 0 for the quotient and the entire
            # dividend as the remainder
            quotient = class_([0])
            remainder = dividend
        else: # dividend_power >= divisor_power
            quotient = class_([0] * dividend_power) # init the quotient array
            # init the remainder to the dividend, and we will divide it sucessively by the quotient major coefficient
            remainder = dividend
            remainder_power = dividend_power
            remainder_coefficient = dividend_coefficient
            while remainder_power >= divisor_power: # Until there's no remainder left (or the remainder cannot be divided anymore by the divisor)
                quotient_power = remainder_power - divisor_power
                quotient_coefficient = remainder_coefficient / divisor_coefficient
                q = class_( [quotient_coefficient] + [0] * quotient_power ) # construct an array with only the quotient major coefficient (we divide the remainder only with the major coeff)
                quotient = quotient + q # add the coeff to the full quotient
                remainder = remainder - q * divisor # divide the remainder with the major coeff quotient multiplied by the divisor, this gives us the new remainder
                remainder_power = remainder.degree # compute the new remainder degree
                remainder_coefficient = remainder[0] # Compute the new remainder coefficient
                #print "quotient: %s remainder: %s" % (quotient, remainder)
        return quotient, remainder

    def __richcmp__(self, other, int op):
        # 0: <
        # 2: ==
        # 4: >
        # 1: <=
        # 3: !=
        # 5: >=
        if op == 2:
            return self.coefficients == other.coefficients
        elif op == 3:
            return self.coefficients != other.coefficients
    def __hash__(self):
        return hash(self.coefficients)

    def __repr__(self):
        n = self.__class__.__name__
        return "%s(%r)" % (n, self.coefficients)
    def __str__(self):
        buf = StringIO()
        cdef int l = self.degree - 1
        for i, c in enumerate(self.coefficients):
            if not c and i > 0:
                continue
            power = l - i
            if c == 1 and power != 0:
                c = ""
            if power > 1:
                buf.write("%sx^%s" % (c, power))
            elif power == 1:
                buf.write("%sx" % c)
            else:
                buf.write("%s" % c)
            buf.write(" + ")
        return buf.getvalue()[:-3]

    cpdef int evaluate(self, int x):
        "Evaluate this polynomial at value x, returning the result."
        # Holds the sum over each term in the polynomial
        cdef int c = 0

        # Holds the current power of x. This is multiplied by x after each term
        # in the polynomial is added up. Initialized to x^0 = 1
        cdef int p = 1

        for term in self.coefficients[::-1]:
            c = c + term * p
            p = p * x

        return c

    cpdef int get_coefficient(self, int degree):
        """Returns the coefficient of the specified term"""
        if degree > self.degree:
            return 0
        else:
            return self.coefficients[-(degree+1)]

    def __iter__(self):
        return iter(self.coefficients)
        #for item in self.coefficients:
            #yield item

    def  __getitem__(self, slice):
        return self.coefficients[slice]