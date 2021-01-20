provide {
  render-chart: render-chart,
  render-charts: render-charts,
  from-list: from-list,
} end

provide-types {
  DataSeries :: DataSeries,
  ChartWindow :: ChartWindow,
}

import global as G
import base as B
include lists
include option
import image-structs as I
import internal-image-untyped as IM
import sets as S
import chart-lib as P
import either as E
import string-dict as SD
import valueskeleton as VS
import statistics as ST
import color as C

################################################################################
# CONSTANTS
################################################################################

SHOW-LENGTH = 3
FUNCTION-POINT-SIZE = 0.1
DEFAULT-RANGE = {-10; 10}

################################################################################
# DATA + TYPE SYNONYMS
################################################################################

type PlottableFunction = (Number -> Number)
type Posn = RawArray<Number>
type TableIntern = RawArray<RawArray<Any>>
data Pointer: 
  | pointer(label :: String, value :: Number)
end
data SciNumber: 
  | sci-notation(coeff :: Number, exponent :: Number, base :: Number)
end
data AxisData: 
  | axis-data(axisTop :: Number, axisBottom :: Number, ticks :: List<Pointer>)
end


################################################################################
# HELPERS
################################################################################

fun check-num(v :: Number) -> Nothing: nothing end
fun check-string(v :: String) -> Nothing: nothing end
fun check-image(v :: IM.Image) -> Nothing: nothing end

fst = raw-array-get(_, 0)
snd = raw-array-get(_, 1)
posn = {(x :: Number, y :: Number): [raw-array: x, y]}

sprintf = (lam():
    generic-sprintf = lam(arr :: RawArray<Any>):
      raw-array-fold(lam(str, elt, _): str + tostring(elt) end, '', arr, 0)
    end
    {
      make5: {(a, b, c, d, e): generic-sprintf([raw-array: a, b, c, d, e])},
      make4: {(a, b, c, d): generic-sprintf([raw-array: a, b, c, d])},
      make3: {(a, b, c): generic-sprintf([raw-array: a, b, c])},
      make2: {(a, b): generic-sprintf([raw-array: a, b])},
      make1: tostring,
      make0: {(): ''},
      make: generic-sprintf
    }
  end)()

unsafe-equal = {(x :: Number, y :: Number): (x <= y) and (y <= x)}

fun to-table2(xs :: List<Any>, ys :: List<Any>) -> TableIntern:
  map2({(x, y): [raw-array: x, y]}, xs, ys) ^ builtins.raw-array-from-list
end

fun to-table3(xs :: List<Any>, ys :: List<Any>, zs :: List<Any>) -> TableIntern:
  map3({(x, y, z): [raw-array: x, y, z]}, xs, ys, zs) ^ builtins.raw-array-from-list
end

fun get-vs-from-img(s :: String, raw-img :: IM.Image) -> VS.ValueSkeleton:
  I.color(190, 190, 190, 0.75)
    ^ IM.text-font(s, 72, _, "", "modern", "normal", "bold", false)
    ^ IM.overlay-align("center", "bottom", _, raw-img)
    ^ VS.vs-value
end

fun table-sorter<A,B>(
    t :: TableIntern, 
    value-getter :: (RawArray -> A), 
    scorer :: (A -> B), 
    cmp :: (B, B -> Boolean), 
    eq :: (B, B -> Boolean)): 
  doc: ```
       General Data Table Sorting Function:
       Value-getter grabs the Column of the Data table you want to use to sort
       Scorer Modifies the values in that Column to what you want to sort-by
       ```
  list-of-rows = t ^ raw-array-to-list

  scored-values = 
    map(
      {(row): {row; row ^ value-getter ^ scorer}}, 
      list-of-rows)

  sorted-by-score = 
    scored-values.sort-by(
      {(row-score, oth-row-score): cmp(row-score.{1}, oth-row-score.{1})}, 
      {(row-score, oth-row-score): eq(row-score.{1}, oth-row-score.{1})})

  sorted-rows = map({(row-score): row-score.{0}}, sorted-by-score)
  sorted-rows ^ builtins.raw-array-from-list
end

fun num-to-scientific(base :: Number) -> (Number -> SciNumber) block: 
  doc: ```
       Produces a function that takes a number and turns it into it's scientific representation. 
       Calculates the resulting Coeff, Exponent where number = coeff * base ^ Exponent.
       Currently only works with bases > 1.
       ```
  when base <= 1: 
    raise("Num-to-scientific: Only defined on bases > 1")
  end
  
  fun recur(s :: SciNumber): 
    doc: ``` 
         Takes the current Coeff, Exponent and divides/multiplies by base to move closer to 
         the actual scientific representation.
         ```
    cases (SciNumber) s: 
      | sci-notation(c, e, b) => 
        pos-c = num-abs(c)
        ask: 
          | (pos-c > 0) and (pos-c < 1) then: recur(sci-notation(c * b, e - 1, b))
          | (pos-c == 0) or ((pos-c >= 1) and (pos-c < b)) then: sci-notation(c, e, b)
          | otherwise: recur(sci-notation(c / b, e + 1, b))
        end
    end
  end
  
  {(n): recur(sci-notation(n, 0, base))}
#|
where: 
  num-to-scientific(10)(0) is sci-notation(0, 0, 10)
  num-to-scientific(10)(3.214) is sci-notation(3.214, 0, 10)
  num-to-scientific(10)(513) is sci-notation(5.13, 2, 10)
  num-to-scientific(10)(-23) is sci-notation(-2.3, 1, 10)
  num-to-scientific(10)(0.00123) is sci-notation(1.23, -3, 10)
  num-to-scientific(10)(-0.0231) is sci-notation(-2.31, -2, 10)
  num-to-scientific(2)(256) is sci-notation(1, 8, 2)
  num-to-scientific(1) raises "Only defined on bases > 1"
  num-to-scientific(0.32) raises "Only defined on bases > 1"
  num-to-scientific(0) raises "Only defined on bases > 1"
  num-to-scientific(-50) raises "Only defined on bases > 1"
|#
end

fun prep-axis(values :: List<Number>) -> {Number; Number}: 
  doc: ``` Calculate the max axis (top) and min axis (bottom) values for bar-chart-series```

  get-with-cmp = {(cmp :: (Number, Number -> Boolean), l :: List<Number>) -> Number: 
    fold({(acc, elm): 
      if cmp(acc, elm): acc
      else: elm
      end}, l.first, l)}

  max-positive-height = num-max(0, get-with-cmp({(a, b): a > b}, values))
  max-negative-height = num-min(0, get-with-cmp({(a, b): a < b}, values))

  {max-positive-height; max-negative-height}
end

fun multi-prep-axis(is-stacked :: String, value-lists :: List<List<Number>>) 
  -> {Number; Number}: 
  doc: ``` 
       Calculate the max axis (top) and min axis (bottom) values for multi-bar-chart-series
       ```

  get-with-cmp = {(cmp :: (Number, Number -> Boolean), l :: List<Number>) -> Number: 
    fold({(acc, elm): 
      if cmp(acc, elm): acc
      else: elm
      end}, l.first, l)}

  ask:
    | is-stacked == 'none' then: 
      # Find the tallest bar in the entire group 
      positive-max-groups = map({(l): get-with-cmp({(a, b): a > b}, l)}, value-lists)
      negative-max-groups = map({(l): get-with-cmp({(a, b): a < b}, l)}, value-lists)
      max-positive-height = num-max(0, get-with-cmp({(a, b): a > b}, positive-max-groups))
      max-negative-height = num-min(0, get-with-cmp({(a, b): a < b}, negative-max-groups))
      {max-positive-height; max-negative-height}

    | is-stacked == 'absolute' then: 
      # Find height of stack using sum functions
      sum = {(l :: List<Number>): fold({(acc, elm): acc + elm}, 0, l)}
      positive-only-sum = {(l :: List<Number>): sum(filter({(e): e >= 0}, l))}
      negative-only-sum = {(l :: List<Number>): sum(filter({(e): e <= 0}, l))}
      positive-sums = map(positive-only-sum, value-lists)
      negative-sums = map(negative-only-sum, value-lists)
      max-positive-height = num-max(0, get-with-cmp({(a, b): a > b}, positive-sums))
      max-negative-height = num-min(0, get-with-cmp({(a, b): a < b}, negative-sums))
      {max-positive-height; max-negative-height}

    | otherwise: 
      has-pos = any({(l): any( _ > 0, l)}, value-lists)
      has-neg = any({(l): any( _ < 0, l)}, value-lists)
      ask: 
        | has-pos and has-neg then: {1; -1}
        | has-pos then: {1; 0}
        | has-neg then: {0; -1}
        | otherwise: {1; -1}
      end
  end
end

################################################################################
# METHODS
################################################################################

color-method = method(self, color :: I.Color):
  self.constr()(self.obj.{color: some(color)})
end

color-list-method = method(self, colors :: List<I.Color>):
  cases (List) colors: 
    | empty => self.constr()(self.obj.{colors: none})
    | link(_, _) => self.constr()(self.obj.{colors: some(colors)})
  end
end

pointer-color-method = method(self, color :: I.Color):
  self.constr()(self.obj.{pointer-color: some(color)})
end

legend-method = method(self, legend :: String):
  self.constr()(self.obj.{legend: legend})
end

show-minor-grid-lines-method = method(self, is-showing :: Boolean):
  self.constr()(self.obj.{show-minor-grid-lines: is-showing})
end

x-axis-method = method(self, x-axis :: String):
  self.constr()(self.obj.{x-axis: x-axis})
end

y-axis-method = method(self, y-axis :: String):
  self.constr()(self.obj.{y-axis: y-axis})
end

x-min-method = method(self, x-min :: Number):
  self.constr()(self.obj.{x-min: some(x-min)})
end

x-max-method = method(self, x-max :: Number):
  self.constr()(self.obj.{x-max: some(x-max)})
end

y-min-method = method(self, y-min :: Number):
  self.constr()(self.obj.{y-min: some(y-min)})
end

y-max-method = method(self, y-max :: Number):
  self.constr()(self.obj.{y-max: some(y-max)})
end

sort-method = method(self, 
    cmp :: (Number, Number -> Boolean), 
    eq :: (Number, Number -> Boolean)): 

  fun get-value(row :: RawArray) -> Number: 
    doc:```
        VALUE GETTER: Gets the values from the row of data in Number form
        ASSUMES the row of data is ordered by [LABEL, VALUES, OTHER]
        ```
    raw-array-get(row, 1)
  end
  
  identity = {(x): x}
  sorted-table = table-sorter(self.obj!tab, get-value, identity, cmp, eq)
  self.constr()(self.obj.{tab: sorted-table})
end

label-sort-method = method(self, 
    cmp :: (String, String -> Boolean), 
    eq :: (String, String -> Boolean)): 
  
  fun get-label(row :: RawArray) -> String: 
    doc:```
        VALUE GETTER: Gets the values from the row of data in Number form
        ASSUMES the row of data is ordered by [LABEL, VALUES, OTHER]
        ```
    raw-array-get(row, 0)
  end
  
  identity = {(x): x}
  sorted-table = table-sorter(self.obj!tab, get-label, identity, cmp, eq)
  self.constr()(self.obj.{tab: sorted-table})
end

multi-sort-method = method(self, 
    scorer :: (List<Number> -> Number), 
    cmp :: (Number, Number -> Boolean), 
    eq :: (Number, Number -> Boolean)): 

  fun get-values(row :: RawArray) -> List<Number>: 
    doc:```
        VALUE GETTER: Gets the values from the row of data in List form
        ASSUMES the row of data is ordered by [LABEL, VALUES, OTHER]
        ```
    raw-array-get(row, 1) ^ raw-array-to-list
  end
  
  sorted-table = table-sorter(self.obj!tab, get-values, scorer, cmp, eq)
  self.constr()(self.obj.{tab: sorted-table})
end

default-multi-sort-method = method(self, 
    cmp :: (Number, Number -> Boolean), 
    eq :: (Number, Number -> Boolean)): 

  fun get-values(row :: RawArray) -> List<Number>: 
    doc:```
        VALUE GETTER: Gets the values from the row of data in List form
        ASSUMES the row of data is ordered by [LABEL, VALUES, OTHER]
        ```
    raw-array-get(row, 1) ^ raw-array-to-list
  end
  
  sum = {(l :: List<Number>): fold({(acc, elm): acc + elm}, 0, l)}
  sorted-table = table-sorter(self.obj!tab, get-values, sum, cmp, eq)
  self.constr()(self.obj.{tab: sorted-table})
end

axis-pointer-method = method(self,
    tickValues :: List<Number>, 
    tickLabels :: List<String>) block: 

  # Lengths of Lists
  TVLen = tickValues.length() 
  TLLen = tickLabels.length()
  distinctTVLen = distinct(tickValues).length()

  # Edge Case Error Checking
  when not(distinctTVLen == TVLen): 
    raise('add-pointers: pointers cannot overlap')
  end
  when not(TVLen == TLLen): 
    raise('add-pointers: pointers values and names should have the same length')
  end

  ticks = fold2({(acc, e1, e2): link(pointer(e1, e2), acc)}, empty, tickLabels, tickValues)
  self.constr()(self.obj.{pointers: some(distinct(ticks))})
end

make-axis-data-method = method(self,  pos-bar-height :: Number, neg-bar-height :: Number):
  step-types = [list: 0, 0.2, 0.25, 0.5, 1, 2]

  # Turn the numbers into Scientific Numbers
  scientific-b10 = num-to-scientific(10)
  pos-sci = scientific-b10(pos-bar-height)
  neg-sci = scientific-b10(neg-bar-height)

  # Calculate the step distance between gridlines
  pos-step = step-types.filter({(n): n >= num-abs(pos-sci.coeff / 9)}).get(0) * num-expt(10, pos-sci.exponent)
  neg-step = step-types.filter({(n): n >= num-abs(neg-sci.coeff / 9)}).get(0) * num-expt(10, neg-sci.exponent)
  step = num-max(pos-step, neg-step)
  step-sci = scientific-b10(step)

  # Use step distance to calculate Axis Properties
  name-tick = 
    {(n): 
      ask:
      | (step-sci.coeff == 2.5) and (step-sci.exponent <= 0) then: 
        pointer(num-to-string-digits(n, 2 - step-sci.exponent), n)
      | step-sci.exponent < 0 then: 
        pointer(num-to-string-digits(n, 1 - step-sci.exponent), n)
      | otherwise: 
        pointer(num-to-string(n), n)
      end}

  axisTop = num-max(0, step * num-ceiling(pos-bar-height / step))
  axisBottom = num-min(0, step * num-floor(neg-bar-height / step))
  pos-ticks = map(name-tick, range-by(0, axisTop + step, step))
  neg-ticks = map(name-tick, range-by(0, axisBottom - step, -1 * step))

  self.constr()(
    self.obj.{axisdata: some(axis-data(axisTop, axisBottom, distinct(pos-ticks + neg-ticks)))}
    )
end

format-axis-data-method = method(self, format-func :: (Number -> String)):
  cases (Option) self.obj!axisdata: 
    | none => 
      raise("Should never have reached this point. Yell at John for not setting up the axis properties somewhere where he should have and please report this as a bug")
    | some(ad) => 
      new-ticks = map({(p): pointer(format-func(p.value), p.value)}, ad.ticks)
      self.constr()(self.obj.{axisdata: some(axis-data(ad.axisTop, ad.axisBottom, new-ticks))})
  end
end

scale-method = method(self, scale-fun :: (Number -> Number)): 
  exact-sf = {(n): n ^ scale-fun ^ num-to-rational}
  list-of-rows = self.obj!tab ^ raw-array-to-list
  scale-row = {(row): [raw-array: raw-array-get(row, 0), raw-array-get(row, 1) ^ exact-sf]}
  scaled-tab = map(scale-row, list-of-rows) ^ builtins.raw-array-from-list
  scaled-self = self.constr()(self.obj.{tab: scaled-tab})
  scaled-values = map({(row): raw-array-get(row, 1) ^ exact-sf}, list-of-rows)
  {max-positive-height; max-negative-height} = prep-axis(scaled-values)

  scaled-self.make-axis(max-positive-height, max-negative-height)
end

multi-scale-method = method(self, scale-fun :: (Number -> Number)): 
  exact-sf = {(n): n ^ scale-fun ^ num-to-rational}
  list-of-rows = self.obj!tab ^ raw-array-to-list
  get-values = {(row): raw-array-get(row, 1) ^ raw-array-to-list}
  scale-row = {(row): [raw-array: raw-array-get(row, 0), map(exact-sf, row ^ get-values) ^ builtins.raw-array-from-list]}
  scaled-tab = map(scale-row, list-of-rows) ^ builtins.raw-array-from-list
  scaled-self = self.constr()(self.obj.{tab: scaled-tab})
  scaled-values = map({(row): map(exact-sf, row ^ get-values)}, list-of-rows)
  {max-positive-height; max-negative-height} = 
    multi-prep-axis(scaled-self.obj!is-stacked, scaled-values)

  scaled-self.make-axis(max-positive-height, max-negative-height)
end

stacking-type-method = method(self, stack-type :: String): 
  get-values = {(row): raw-array-get(row, 1) ^ raw-array-to-list}
  value-lists = map(get-values, self.obj!tab ^ raw-array-to-list)
  ask: 
    | stack-type == 'absolute' then: 
      new-self = self.constr()(self.obj.{is-stacked: 'absolute'})
      {max-positive-height; max-negative-height} = 
        multi-prep-axis('absolute', value-lists)
      new-self.make-axis(max-positive-height, max-negative-height)
    | stack-type == 'relative' then: 
      new-self = self.constr()(self.obj.{is-stacked: 'relative'})
      {max-positive-height; max-negative-height} = 
        multi-prep-axis('relative', value-lists)
      new-self.make-axis(max-positive-height, max-negative-height)
    | stack-type == 'percent' then:
      new-self = self.constr()(self.obj.{is-stacked: 'percent'})
      {max-positive-height; max-negative-height} = 
        multi-prep-axis('percent', value-lists)
      new-self.make-axis(max-positive-height, max-negative-height)
              .format-axis({(n): num-to-string(n * 100) + "%"})
    | stack-type == 'none' then: 
      new-self = self.constr()(self.obj.{is-stacked: 'none'})
      {max-positive-height; max-negative-height} = 
        multi-prep-axis('none', value-lists)
      new-self.make-axis(max-positive-height, max-negative-height)
    | otherwise: raise('stacking-type: type must be absolute, relative, percent, or none')
  end
end

################################################################################
# BOUNDING BOX
################################################################################

type BoundingBox = {
  x-min :: Number,
  x-max :: Number,
  y-min :: Number,
  y-max :: Number,
  is-valid :: Boolean
}
default-bounding-box :: BoundingBox = {
  x-min: 0,
  x-max: 0,
  y-min: 0,
  y-max: 0,
  is-valid: false,
}

fun get-bounding-box(ps :: List<Posn>) -> BoundingBox:
  cases (List<Number>) ps:
    | empty => default-bounding-box.{is-valid: false}
    | link(f, r) =>
      fun compute(p :: (Number, Number -> Number), accessor :: (Posn -> Number)):
        for fold(prev from accessor(f), e from r): p(prev, accessor(e)) end
      end
      default-bounding-box.{
        x-min: compute(num-min, fst),
        x-max: compute(num-max, fst),
        y-min: compute(num-min, snd),
        y-max: compute(num-max, snd),
        is-valid: true,
      }
  end
end

fun merge-bounding-box(bs :: List<BoundingBox>) -> BoundingBox:
  for fold(prev from default-bounding-box, e from bs):
    ask:
      | e.is-valid and prev.is-valid then:
        default-bounding-box.{
          x-min: num-min(e.x-min, prev.x-min),
          x-max: num-max(e.x-max, prev.x-max),
          y-min: num-min(e.y-min, prev.y-min),
          y-max: num-max(e.y-max, prev.y-max),
          is-valid: true,
        }
      | e.is-valid then: e
      | prev.is-valid then: prev
      | otherwise: default-bounding-box
    end
  end
end

################################################################################
# DEFAULT VALUES
################################################################################

type BoxChartSeries = {
  tab :: TableIntern,
  height :: Number,
  horizontal :: Boolean
}

default-box-plot-series = {
  horizontal: false,
  show-outliers: true
}

type PieChartSeries = {
  tab :: TableIntern,
}

default-pie-chart-series = {}

type BarChartSeries = {
  tab :: TableIntern,
  axisdata :: Option<AxisData>, 
  color :: Option<I.Color>,
  colors :: Option<List<I.Color>>,
  pointers :: Option<List<Pointer>>, 
  pointer-color :: Option<I.Color>, 
  horizontal :: Boolean
}

default-bar-chart-series = {
  color: none,
  colors: none,
  pointers: none, 
  pointer-color: none,
  axisdata: none, 
  horizontal: false 
}

type MultiBarChartSeries = { 
  tab :: TableIntern,
  axisdata :: Option<AxisData>,
  legends :: RawArray<String>,
  is-stacked :: String,
  colors :: Option<List<I.Color>>, 
  pointers :: Option<List<Pointer>>, 
  pointer-color :: Option<I.Color>, 
  horizontal :: Boolean
}

default-multi-bar-chart-series = {
  is-stacked: 'none',
  colors: some([list: C.red, C.blue, C.green, C.orange, C.purple, C.black, C.brown]),
  pointers: none, 
  pointer-color: none,
  axisdata: none, 
  horizontal: false 
}
  
type HistogramSeries = {
  tab :: TableIntern,
  bin-width :: Option<Number>,
  max-num-bins :: Option<Number>,
  min-num-bins :: Option<Number>,
}

default-histogram-series = {
  bin-width: none,
  max-num-bins: none,
  min-num-bins: none,
}

type LinePlotSeries = {
  ps :: List<Posn>,
  color :: Option<I.Color>,
  legend :: String,
}

default-line-plot-series = {
  color: none,
  legend: '',
}

type ScatterPlotSeries = {
  ps :: List<Posn>,
  color :: Option<I.Color>,
  legend :: String,
  point-size :: Number,
}

default-scatter-plot-series = {
  color: none,
  legend: '',
  point-size: 7,
}

type FunctionPlotSeries = {
  f :: PlottableFunction,
  color :: Option<I.Color>,
  legend :: String,
}

default-function-plot-series = {
  color: none,
  legend: '',
}

###########

type ChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  render :: ( -> IM.Image)
}

default-chart-window-object :: ChartWindowObject = {
  title: '',
  width: 800,
  height: 600,
  method render(self): raise('unimplemented') end,
}

type BoxChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  x-axis :: String,
  y-axis :: String,
  render :: ( -> IM.Image),
}

default-box-plot-chart-window-object :: BoxChartWindowObject = default-chart-window-object.{
  x-axis: '',
  y-axis: '',
}

type PieChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  render :: ( -> IM.Image),
}

default-pie-chart-window-object :: PieChartWindowObject = default-chart-window-object

type BarChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  render :: ( -> IM.Image),
  x-axis :: String,
  y-axis :: String,
  y-min :: Option<Number>,
  y-max :: Option<Number>,
}

default-bar-chart-window-object :: BarChartWindowObject = default-chart-window-object.{
  x-axis: '',
  y-axis: '',
  y-min: none,
  y-max: none,
}

type HistogramChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  render :: ( -> IM.Image),
  x-axis :: String,
  y-axis :: String,
  x-min :: Option<Number>,
  x-max :: Option<Number>,
  y-max :: Option<Number>,
}

default-histogram-chart-window-object :: HistogramChartWindowObject =
  default-chart-window-object.{
    x-axis: '',
    y-axis: '',
    x-min: none,
    x-max: none,
    y-max: none,
  }

type PlotChartWindowObject = {
  title :: String,
  width :: Number,
  height :: Number,
  render :: ( -> IM.Image),
  x-axis :: String,
  y-axis :: String,
  x-min :: Option<Number>,
  x-max :: Option<Number>,
  x-max :: Option<Number>,
  y-max :: Option<Number>,
  num-samples :: Number,
}

default-plot-chart-window-object :: PlotChartWindowObject = default-chart-window-object.{
  x-axis: '',
  y-axis: '',
  show-minor-grid-lines: false,
  x-min: none,
  x-max: none,
  y-min: none,
  y-max: none,
  num-samples: 1000,
}

################################################################################
# DATA DEFINITIONS
################################################################################

data DataSeries:
  | line-plot-series(obj :: LinePlotSeries) with:
    is-single: false,
    constr: {(): line-plot-series},
    color: color-method,
    legend: legend-method,
  | scatter-plot-series(obj :: ScatterPlotSeries) with:
    is-single: false,
    constr: {(): scatter-plot-series},
    color: color-method,
    legend: legend-method,
    method point-size(self, point-size :: Number):
      scatter-plot-series(self.obj.{point-size: point-size})
    end,
  | function-plot-series(obj :: FunctionPlotSeries) with:
    is-single: false,
    constr: {(): function-plot-series},
    color: color-method,
    legend: legend-method,
  | pie-chart-series(obj :: PieChartSeries) with:
    is-single: true,
    constr: {(): pie-chart-series},
  | bar-chart-series(obj :: BarChartSeries) with:
    is-single: true,
    default-color: color-method, 
    colors: color-list-method,
    sort-by: sort-method,
    sort-by-label: label-sort-method,
    add-pointers: axis-pointer-method,
    pointer-color: pointer-color-method,
    format-axis: format-axis-data-method, 
    make-axis: make-axis-data-method, 
    scale: scale-method, 
    method horizontal(self, b :: Boolean):
      self.constr()(self.obj.{horizontal: b})
    end,
    constr: {(): bar-chart-series},
  | multi-bar-chart-series(obj :: MultiBarChartSeries) with: 
    is-single: true,
    colors: color-list-method,
    sort-by: default-multi-sort-method,
    sort-by-data: multi-sort-method, 
    sort-by-label: label-sort-method,
    add-pointers: axis-pointer-method, 
    pointer-color: pointer-color-method,
    format-axis: format-axis-data-method,
    make-axis: make-axis-data-method,
    scale: multi-scale-method,
    stacking-type: stacking-type-method, 
    method horizontal(self, b :: Boolean):
      self.constr()(self.obj.{horizontal: b})
    end,
    constr: {(): multi-bar-chart-series}
  | box-plot-series(obj :: BoxChartSeries) with:
    is-single: true,
    constr: {(): box-plot-series},
    method horizontal(self, h):
      self.constr()(self.obj.{horizontal: h})
    end,
    method show-outliers(self, show):
      self.constr()(self.obj.{show-outliers: show})
    end
  | histogram-series(obj :: HistogramSeries) with:
    is-single: true,
    constr: {(): histogram-series},
    method bin-width(self, bin-width :: Number):
      histogram-series(self.obj.{bin-width: some(bin-width)})
    end,
    method max-num-bins(self, max-num-bins :: Number):
      histogram-series(self.obj.{max-num-bins: some(max-num-bins)})
    end,
    method min-num-bins(self, min-num-bins :: Number):
      histogram-series(self.obj.{min-num-bins: some(min-num-bins)})
    end,
    method num-bins(self, num-bins :: Number):
      histogram-series(self.obj.{
        min-num-bins: some(num-bins),
        max-num-bins: some(num-bins)
      })
    end,
sharing:
  method _output(self):
    get-vs-from-img("DataSeries", render-chart(self).get-image())
  end
end

fun check-chart-window(p :: ChartWindowObject) -> Nothing:
  if (p.width <= 0) or (p.height <= 0):
    raise('render: width and height must be positive')
  else:
    nothing
  end
end

data ChartWindow:
  | pie-chart-window(obj :: PieChartWindowObject) with:
    constr: {(): pie-chart-window},
  | box-plot-chart-window(obj :: BoxChartWindowObject) with:
    constr: {(): box-plot-chart-window},
    x-axis: x-axis-method,
    y-axis: y-axis-method,
  | bar-chart-window(obj :: BarChartWindowObject) with:
    constr: {(): bar-chart-window},
    x-axis: x-axis-method,
    y-axis: y-axis-method,
    y-min: y-min-method,
    y-max: y-max-method,
  | histogram-chart-window(obj :: HistogramChartWindowObject) with:
    constr: {(): histogram-chart-window},
    x-axis: x-axis-method,
    y-axis: y-axis-method,
    x-min: x-min-method,
    x-max: x-max-method,
    y-max: y-max-method,
  | plot-chart-window(obj :: PlotChartWindowObject) with:
    constr: {(): plot-chart-window},
    show-minor-grid-lines: show-minor-grid-lines-method,
    x-axis: x-axis-method,
    y-axis: y-axis-method,
    x-min: x-min-method,
    x-max: x-max-method,
    y-min: y-min-method,
    y-max: y-max-method,
    method num-samples(self, num-samples :: Number) block:
      when (num-samples <= 0) or (num-samples > 100000) or not(num-is-integer(num-samples)):
        raise('num-samples: value must be an ineger between 1 and 100000')
      end
      plot-chart-window(self.obj.{num-samples: num-samples})
    end,
sharing:
  method display(self):
    _ = check-chart-window(self.obj)
    self.obj.{interact: true}.render()
  end,
  method get-image(self):
    _ = check-chart-window(self.obj)
    self.obj.{interact: false}.render()
  end,
  method title(self, title :: String):
    self.constr()(self.obj.{title: title})
  end,
  method width(self, width :: Number):
    self.constr()(self.obj.{width: width})
  end,
  method height(self, height :: Number):
    self.constr()(self.obj.{height: height})
  end,
  method _output(self):
    get-vs-from-img("ChartWindow", self.get-image())
  end
end

################################################################################
# FUNCTIONS
################################################################################

fun function-plot-from-list(f :: PlottableFunction) -> DataSeries:
  default-function-plot-series.{
    f: f,
  } ^ function-plot-series
end

fun line-plot-from-list(xs :: List<Number>, ys :: List<Number>) -> DataSeries block:
  when xs.length() <> ys.length():
    raise('line-plot: xs and ys should have the same length')
  end
  xs.each(check-num)
  ys.each(check-num)
  default-line-plot-series.{
    ps: map2({(x, y): [raw-array: x, y]}, xs, ys)
  } ^ line-plot-series
end

fun scatter-plot-from-list(xs :: List<Number>, ys :: List<Number>) -> DataSeries block:
  when xs.length() <> ys.length():
    raise('scatter-plot: xs and ys should have the same length')
  end
  xs.each(check-num)
  ys.each(check-num)
  default-scatter-plot-series.{
    ps: map4({(x, y, z, img): [raw-array: x, y, z, img]}, xs, ys, xs.map({(_): ''}), xs.map({(_): false}))
  } ^ scatter-plot-series
end

fun labeled-scatter-plot-from-list(
  labels :: List<String>,
  xs :: List<Number>,
  ys :: List<Number>) -> DataSeries block:
  when xs.length() <> ys.length():
    raise('labeled-scatter-plot: xs and ys should have the same length')
  end
  when xs.length() <> labels.length():
    raise('labeled-scatter-plot: xs and labels should have the same length')
  end
  xs.each(check-num)
  ys.each(check-num)
  labels.each(check-string)
  default-scatter-plot-series.{
    ps: map4({(x, y, z, img): [raw-array: x, y, z, img]}, xs, ys, labels, xs.map({(_): false}))
  } ^ scatter-plot-series
end

fun image-scatter-plot-from-list(
  images :: List<IM.Image>,
  xs :: List<Number>,
  ys :: List<Number>) -> DataSeries block:
  when xs.length() <> ys.length():
    raise('labeled-scatter-plot: xs and ys should have the same length')
  end
  when xs.length() <> images.length():
    raise('labeled-scatter-plot: xs and images should have the same length')
  end
  xs.each(check-num)
  ys.each(check-num)
  images.each(check-image)
  default-scatter-plot-series.{
    ps: map4({(x, y, z, img): [raw-array: x, y, z, img]}, xs, ys, xs.map({(_): ''}), images)
  } ^ scatter-plot-series
end

fun exploding-pie-chart-from-list(
  labels :: List<String>,
  values :: List<Number>,
  offsets :: List<Number>
) -> DataSeries block:
  label-length = labels.length()
  value-length = values.length()
  when label-length <> value-length:
    raise('exploding-pie-chart: labels and values should have the same length')
  end
  offset-length = offsets.length()
  when label-length <> offset-length:
    raise('exploding-pie-chart: labels and offsets should have the same length')
  end
  when label-length == 0:
    raise('exploding-pie-chart: need at least one data')
  end
  for each(offset from offsets):
    when (offset < 0) or (offset > 1):
      raise('exploding-pie-chart: offset must be between 0 and 1')
    end
  end
  values.each(check-num)
  offsets.each(check-num)
  labels.each(check-string)
  default-pie-chart-series.{
    tab: to-table3(labels, values, offsets)
  } ^ pie-chart-series
end

fun pie-chart-from-list(labels :: List<String>, values :: List<Number>) -> DataSeries block:
  doc: ```
       Consume labels, a list of string, and values, a list of numbers
       and construct a pie chart
       ```
  label-length = labels.length()
  value-length = values.length()
  when label-length <> value-length:
    raise('pie-chart: labels and values should have the same length')
  end
  when label-length == 0:
    raise('pie-chart: need at least one data')
  end
  values.each(check-num)
  labels.each(check-string)
  default-pie-chart-series.{
    tab: to-table3(labels, values, labels.map({(_): 0}))
  } ^ pie-chart-series
end

fun bar-chart-from-list(labels :: List<String>, values :: List<Number>) -> DataSeries block:
  doc: ```
       Consume labels, a list of string, and values, a list of numbers
       and construct a bar chart
       ```
  # Constants
  label-length = labels.length()
  value-length = values.length()
  rational-values = map(num-to-rational, values)

  # Edge Case Error Checking
  when value-length == 0:
    raise("bar-chart: can't have empty data")
  end
  when label-length <> value-length:
    raise('bar-chart: labels and values should have the same length')
  end

  # Type Checking
  rational-values.each(check-num)
  labels.each(check-string)

  {max-positive-height; max-negative-height} = prep-axis(rational-values)

  data-series = default-bar-chart-series.{
    tab: to-table2(labels, rational-values)
  } ^ bar-chart-series

  data-series.make-axis(max-positive-height, max-negative-height)
end

fun grouped-bar-chart-from-list(
  labels :: List<String>,
  value-lists :: List<List<Number>>,
  legends :: List<String>
) -> DataSeries block:
  doc: ```
       Produces a grouped bar chart where labels are bar group names, legends are bar names, 
       and value-lists contains the data of each bar seperated into seperate groups 
       ```
  # Constants
  label-length = labels.length()
  value-length = value-lists.length()
  legend-length = legends.length() 
  rational-values = value-lists.map({(row): map(num-to-rational, row)})

  # Edge Case Error Checking 
  when value-length == 0:
    raise("grouped-bar-chart: can't have empty data")
  end
  when legend-length == 0: 
    raise("grouped-bar-chart: can't have empty legends")
  end
  when label-length <> value-length:
    raise('grouped-bar-chart: labels and values should have the same length')
  end
  when any({(group): legend-length <> group.length()}, value-lists):
    raise('grouped-bar-chart: labels and legends should have the same length')
  end
  
  # Typechecking each input
  value-lists.each(_.each(check-num))
  labels.each(check-string)
  legends.each(check-string)

 {max-positive-height; max-negative-height} = multi-prep-axis('none', rational-values)

  # Constructing the Data Series
  data-series = default-multi-bar-chart-series.{
    tab: to-table2(labels, map(builtins.raw-array-from-list, rational-values)),
    legends: legends ^ builtins.raw-array-from-list
  } ^ multi-bar-chart-series

  data-series.make-axis(max-positive-height, max-negative-height)
end

fun stacked-bar-chart-from-list(
  labels :: List<String>,
  value-lists :: List<List<Number>>,
  legends :: List<String>
) -> DataSeries block:
  doc: ```
       Produces a stacked bar chart where labels are bar stack names, legends are bar names, 
       and value-lists contains the data of each bar seperated into seperate stacks 
       ```
  # Constants
  label-length = labels.length()
  value-length = value-lists.length()
  legend-length = legends.length() 
  rational-values = value-lists.map({(row): map(num-to-rational, row)})

  # Edge Case Error Checking 
  when value-length == 0:
    raise("stacked-bar-chart: can't have empty data")
  end
  when legend-length == 0: 
    raise("stacked-bar-chart: can't have empty legends")
  end
  when label-length <> value-length:
    raise('stacked-bar-chart: labels and values should have the same length')
  end
  when any({(stack): legend-length <> stack.length()}, value-lists):
    raise('stacked-bar-chart: labels and legends should have the same length')
  end
  
  # Typechecking the input 
  value-lists.each(_.each(check-num))
  labels.each(check-string)
  legends.each(check-string)

  {max-positive-height; max-negative-height} = multi-prep-axis('absolute', rational-values)

  # Constructing the Data Series
  data-series = default-multi-bar-chart-series.{
    tab: to-table2(labels, rational-values.map(builtins.raw-array-from-list)),
    legends: legends ^ builtins.raw-array-from-list,
    is-stacked: 'absolute'
  } ^ multi-bar-chart-series

  data-series.make-axis(max-positive-height, max-negative-height)
end

fun box-plot-from-list(values :: List<List<Number>>) -> DataSeries:
  doc: "Consunum-maxme values, a list of list of numbers and construct a box chart"
  labels = for map_n(i from 1, _ from values): [sprintf: 'Box ', i] end
  labeled-box-plot-from-list(labels, values)
end

fun labeled-box-plot-from-list(
  labels :: List<String>,
  values :: List<List<Number>>
) -> DataSeries block:
  doc: ```
       Consume labels, a list of string, and values, a list of list of numbers
       and construct a box chart
       ```
  label-length = labels.length()
  value-length = values.length()
  when label-length <> value-length:
    raise('labeled-box-plot: labels and values should have the same length')
  end
  when label-length == 0:
    raise('labeled-box-plot: expect at least one box')
  end
  values.each(_.each(check-num))
  values.each(
    lam(lst):
      when lst.length() <= 1:
        raise('labeled-box-plot: the list length should be at least 2')
      end
    end)
  labels.each(check-string)

  max-height = for fold(cur from values.first.first, lst from values):
    num-max(lst.rest.foldl(num-max, lst.first), cur)
  end
  min-height = for fold(cur from values.first.first, lst from values):
    num-max(lst.rest.foldl(num-min, lst.first), cur)
  end

  fun get-box-data(label :: String, lst :: List<Number>) -> RawArray:
    n = lst.length()
    shadow lst = lst.sort()
    median = ST.median(lst)
    {first-quartile; third-quartile} = if num-modulo(n, 2) == 0:
      splitted = lst.split-at(n / 2)
      {ST.median(splitted.prefix); ST.median(splitted.suffix)}
    else:
      splitted = lst.split-at((n - 1) / 2)
      {ST.median(splitted.prefix); ST.median(splitted.suffix.rest)}
    end
    iqr = third-quartile - first-quartile
    high-outliers = for filter(shadow n from lst):
      n > (third-quartile + (1.5 * iqr))
    end ^ builtins.raw-array-from-list
    low-outliers = for filter(shadow n from lst):
      n < (third-quartile - (1.5 * iqr))
    end ^ builtins.raw-array-from-list
    min-val = lst.first
    max-val = lst.last()
    low-whisker = lst.drop(raw-array-length(low-outliers)).get(0)
    high-whisker = lst.get(n - raw-array-length(high-outliers) - 1)
    [list: label, max-val, min-val, first-quartile, median, third-quartile, high-whisker, low-whisker, high-outliers, low-outliers]
      ^ builtins.raw-array-from-list
  end
  default-box-plot-series.{
    tab: map2(get-box-data, labels, values) ^ builtins.raw-array-from-list,
    height: num-ceiling(max-height + ((max-height - min-height) / 5)),
  } ^ box-plot-series
end

fun freq-bar-chart-from-list(label :: List<String>) -> DataSeries:
  dict = for fold(prev from [SD.string-dict: ], e from label):
    prev.set(e, prev.get(e).or-else(0) + 1)
  end
  {ls; vs; _} = for fold({ls; vs; seen} from {empty; empty; S.empty-tree-set},
      e from label):
    if seen.member(e):
      {ls; vs; seen}
    else:
      {link(e, ls); link(dict.get-value(e), vs); seen.add(e)}
    end
  end
  bar-chart-from-list(ls.reverse(), vs.reverse())
end

fun histogram-from-list(values :: List<Number>) -> DataSeries block:
  doc: ```
       Consume a list of numbers and construct a histogram
       ```
  values.each(check-num)
  default-histogram-series.{
    tab: to-table2(values.map({(_): ''}), values),
  } ^ histogram-series
end

fun labeled-histogram-from-list(labels :: List<String>, values :: List<Number>) -> DataSeries block:
  doc: ```
       Consume a list of strings and a list of numbers and construct a histogram
       ```
  label-length = labels.length()
  value-length = values.length()
  when label-length <> value-length:
    raise('labeled-histogram: labels and values should have the same length')
  end
  values.each(check-num)
  labels.each(check-string)
  default-histogram-series.{
    tab: to-table2(labels, values),
  } ^ histogram-series
end

################################################################################
# PLOTS
################################################################################

fun check-render-x-axis(self) -> Nothing:
  cases (Option) self.x-min:
    | some(x-min) =>
      cases (Option) self.x-max:
        | some(x-max) =>
          if x-min >= x-max:
            raise("render: x-min must be strictly less than x-max")
          else:
            nothing
          end
        | else => nothing
      end
    | else => nothing
  end
end

fun check-render-y-axis(self) -> Nothing:
  cases (Option) self.y-min:
    | some(y-min) =>
      cases (Option) self.y-max:
        | some(y-max) =>
          if y-min >= y-max:
            raise("render: y-min must be strictly less than y-max")
          else:
            nothing
          end
        | else => nothing
      end
    | else => nothing
  end
end

fun render-chart(s :: DataSeries) -> ChartWindow:
  doc: 'Render it!'
  cases (DataSeries) s:
    | line-plot-series(_) => render-charts([list: s])
    | function-plot-series(_) => render-charts([list: s])
    | scatter-plot-series(_) => render-charts([list: s])
    | pie-chart-series(obj) =>
      default-pie-chart-window-object.{
        method render(self): P.pie-chart(self, obj) end
      } ^ pie-chart-window
    | bar-chart-series(obj) =>
      default-bar-chart-window-object.{
        method render(self):
          _ = check-render-y-axis(self)
          P.bar-chart(self, obj)
        end
      } ^ bar-chart-window
    | multi-bar-chart-series(obj) => 
      default-bar-chart-window-object.{
        method render(self):
          _ = check-render-y-axis(self)
          P.multi-bar-chart(self, obj)
        end
      } ^ bar-chart-window
    | box-plot-series(obj) =>
      default-box-plot-chart-window-object.{
        method render(self):
          P.box-plot(self, obj)
        end
      } ^ box-plot-chart-window
    | histogram-series(obj) =>
      default-histogram-chart-window-object.{
        method render(self):
          shadow self = self.{y-min: none}
          _ = check-render-x-axis(self)
          _ = check-render-y-axis(self)
          P.histogram(self, obj)
        end
      } ^ histogram-chart-window
  end
where:
  render-now = {(x): render-chart(x).get-image()}

  render-now(from-list.exploding-pie-chart(
      [list: 'asd', 'dsa', 'qwe'],
      [list: 1, 2, 3],
      [list: 0, 0.1, 0.2])) does-not-raise
  render-now(from-list.pie-chart([list: 'asd', 'dsa', 'qwe'], [list: 1, 2, 3])) does-not-raise
  render-now(from-list.histogram([list: 1, 1.2, 2, 3, 10, 3, 6, -1])) does-not-raise
  render-now(from-list.labeled-histogram(
      [list: 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
      [list: 1, 1.2, 2, 3, 10, 3, 6, -1])) does-not-raise
  render-now(from-list.grouped-bar-chart(
      [list: 'CA', 'TX', 'NY', 'FL', 'IL', 'PA'],
      [list:
        [list: 2704659,4499890,2159981,3853788,10604510,8819342,4114496],
        [list: 2027307,3277946,1420518,2454721,7017731,5656528,2472223],
        [list: 1208495,2141490,1058031,1999120,5355235,5120254,2607672],
        [list: 1140516,1938695,925060,1607297,4782119,4746856,3187797],
        [list: 894368,1558919,725973,1311479,3596343,3239173,1575308],
        [list: 737462,1345341,679201,1203944,3157759,3414001,1910571]],
      [list:
        'Under 5 Years',
        '5 to 13 Years',
        '14 to 17 Years',
        '18 to 24 Years',
        '25 to 44 Years',
        '45 to 64 Years',
        '65 Years and Over'])) does-not-raise
  render-now(from-list.stacked-bar-chart(
      [list: 'CA', 'TX', 'NY', 'FL', 'IL', 'PA'],
      [list:
        [list: 2704659,4499890,2159981,3853788,10604510,8819342,4114496],
        [list: 2027307,3277946,1420518,2454721,7017731,5656528,2472223],
        [list: 1208495,2141490,1058031,1999120,5355235,5120254,2607672],
        [list: 1140516,1938695,925060,1607297,4782119,4746856,3187797],
        [list: 894368,1558919,725973,1311479,3596343,3239173,1575308],
        [list: 737462,1345341,679201,1203944,3157759,3414001,1910571]],
      [list:
        'Under 5 Years',
        '5 to 13 Years',
        '14 to 17 Years',
        '18 to 24 Years',
        '25 to 44 Years',
        '45 to 64 Years',
        '65 Years and Over'])) does-not-raise
  render-now(from-list.function-plot(num-sin)) does-not-raise
  render-now(from-list.scatter-plot(
      [list: 1, 1, 4, 7, 4, 2],
      [list: 2, 3.1, 1, 3, 6, 5])) does-not-raise
  render-now(from-list.line-plot(
      [list: 1, 1, 4, 7, 4, 2],
      [list: 2, 3.1, 1, 3, 6, 5])) does-not-raise
  render-now(from-list.box-plot(
      [list: [list: 1, 2, 3, 4], [list: 1, 2, 3, 4, 5], [list: 10, 11]]
    )) does-not-raise
end

fun generate-xy(
    p :: FunctionPlotSeries,
    x-min :: Number,
    x-max :: Number,
    num-samples :: Number) -> ScatterPlotSeries:
  doc: 'Generate a scatter-plot from an function-plot'
  fraction = (x-max - x-min) / (num-samples - 1)

  ps = for filter-map(i from range(0, num-samples)):
    x = x-min + (fraction * i)
    cases (E.Either) run-task({(): p.f(x)}):
      | left(y) => some([raw-array: x, y])
      | right(_) => none
    end
  end

  default-scatter-plot-series.{
    ps: ps,
    point-size: FUNCTION-POINT-SIZE,
    color: p.color,
    legend: p.legend,
  }
where:
  generate-xy(from-list.function-plot(_ + 1).obj, 0, 100, 6).ps
    is=~ [list:
    posn(0, 1),
    posn(20, 21),
    posn(40, 41),
    posn(60, 61),
    posn(80, 81),
    posn(100, 101) # out of bound, will be filtered later
  ]
end

fun widen-range(min :: Number, max :: Number) -> {Number; Number}:
  offset = num-min((max - min) / 40, 1)
  shadow offset = if unsafe-equal(offset, 0): 1 else: offset end
  {min - offset; max + offset}
end

fun ps-to-arr(obj): obj.{ps: obj.ps ^ builtins.raw-array-from-list} end

fun in-bound-x(p :: Posn, self) -> Boolean:
  (self.x-min.value <= fst(p)) and (fst(p) <= self.x-max.value)
end

fun in-bound-y(p :: Posn, self) -> Boolean:
  (self.y-min.value <= snd(p)) and (snd(p) <= self.y-max.value)
end

fun in-bound-xy(p :: Posn, self) -> Boolean:
  in-bound-x(p, self) and in-bound-y(p, self)
end

fun dist(a :: Posn, b :: Posn) -> Number:
  num-sqr(fst(a) - fst(b)) + num-sqr(snd(a) - snd(b))
end

fun nearest(lst :: List<Posn>, p :: Posn) -> Option<Posn>:
  cases (List<Posn>) lst:
    | empty => none
    | link(f, r) =>
      {_; sol} = for fold({best; sol} from {dist(p, f); f}, e from lst):
        new-dist = dist(p, e)
        if new-dist < best:
          {new-dist; e}
        else:
          {best; sol}
        end
      end
      some(sol)
  end
end

fun find-pt-on-edge(in :: Posn, out :: Posn, self) -> Option<Posn>:
  px-max = num-min(num-max(fst(in), fst(out)), self.x-max.value)
  px-min = num-max(num-min(fst(in), fst(out)), self.x-min.value)
  py-max = num-min(num-max(snd(in), snd(out)), self.y-max.value)
  py-min = num-max(num-min(snd(in), snd(out)), self.y-min.value)

  candidates = if unsafe-equal(fst(in), fst(out)):
    [list: posn(fst(in), self.y-min.value), posn(fst(in), self.y-max.value)]
  else:
    #|
    y = m * x + c           [3]
    y2 = m * x2 + c         [3.1]
    y - y2 = m * (x - x2)   [5]   [by 3 - 3.1]
    m = (y - y2) / (x - x2) [1]   [rewrite 5]
    c = y - m * x           [2]   [rewrite 3]
    x = (y - c) / m         [4]   [rewrite 3]
    |#
    m = (snd(in) - snd(out)) / (fst(in) - fst(out)) # [1]
    c = snd(in) - (m * fst(in)) # [2]
    f = {(x): (m * x) + c} # [3]
    g = {(y): (y - c) / m} # [4]

    [list:
      posn(self.x-min.value, f(self.x-min.value)),
      posn(self.x-max.value, f(self.x-max.value))] +
    if unsafe-equal(m, 0):
      empty
    else:
      [list:
        posn(g(self.y-min.value), self.y-min.value),
        posn(g(self.y-max.value), self.y-max.value)]
    end
  end
  candidates.filter({(p): (px-min <= fst(p)) and (fst(p) <= px-max) and
                          (py-min <= snd(p)) and (snd(p) <= py-max)})
    ^ nearest(_, in)
end

fun line-plot-edge-cut(pts :: List<Posn>, self) -> List<Posn>:
  segments = cases (List<Posn>) pts:
    | empty => empty
    | link(f, r) =>
      {segments; _} = for fold({segments; start} from {empty; f}, stop from r):
        segment = ask:
          | in-bound-xy(start, self) and in-bound-xy(stop, self) then:
            [list: start, stop]
          | in-bound-xy(start, self) then:
            result = find-pt-on-edge(start, stop, self).value
            if unsafe-equal(fst(start), fst(result)) and
               unsafe-equal(snd(start), snd(result)):
              [list: start, find-pt-on-edge(stop, start, self).value]
            else:
              [list: start, result]
            end
          | in-bound-xy(stop, self) then:
            [list: find-pt-on-edge(start, stop, self).value, stop]
          | otherwise:
            cases (Option) find-pt-on-edge(start, stop, self):
              | none => empty
              | some(result) =>
                result2 = find-pt-on-edge(stop, start, self).value
                [list: result, result2]
            end
        end
        cases (List) segment:
          | empty => {segments; stop}
          | link(_, _) => {link(segment, segments); stop}
        end
      end
      segments
  end

  cases (List) segments:
    | empty => empty
    | link(f, r) =>
      {_; result} = for fold({prev; lst} from {f; f}, segment from r):
        pt-a = prev.get(0)
        pt-b = segment.get(1)
        new-lst = if unsafe-equal(fst(pt-a), fst(pt-b)) and unsafe-equal(snd(pt-a), snd(pt-b)):
          link(segment.get(0), lst)
        else:
          segment + link([raw-array: ], lst)
        end
        {segment; new-lst}
      end
      result
  end
end

data BoundResult:
  | exact-bound(n :: Number)
  | inferred-bound(n :: Number)
  | unknown-bound
end

fun bound-result-to-bounds(b-min :: BoundResult, b-max :: BoundResult) -> {Option<Number>; Option<Number>}:
  {l; r} = cases (BoundResult) b-min:
    | exact-bound(v-min) =>
      cases (BoundResult) b-max:
        | exact-bound(v-max) => {v-min; v-max}
        | inferred-bound(v-max) => {v-min; widen-range(v-min, v-max).{1}}
        | unknown-bound => {v-min; v-min + 10}
      end
    | inferred-bound(v-min) =>
      cases (BoundResult) b-max:
        | exact-bound(v-max) => {widen-range(v-min, v-max).{0}; v-max}
        | inferred-bound(v-max) => widen-range(v-min, v-max)
        | unknown-bound => {v-min - 1; (v-min - 1) + 10}
      end
    | unknown-bound =>
      cases (BoundResult) b-max:
        | exact-bound(v-max) => {v-max - 10; v-max}
        | inferred-bound(v-max) => {(v-max + 1) - 10; v-max + 1}
        | unknown-bound => {-10; 10}
      end
  end
  {some(l); some(r)}
end

fun get-bound-result(
  d :: Option<Number>,
  bbox :: BoundingBox,
  f :: (BoundingBox -> Number)
) -> BoundResult:
  cases (Option) d:
    | none => if bbox.is-valid: inferred-bound(f(bbox)) else: unknown-bound end
    | some(v) => exact-bound(v)
  end
end

fun render-charts(lst :: List<DataSeries>) -> ChartWindow:
  doc: "Draw 'em all"
  _ = cases (Option) find(_.is-single, lst):
    | some(v) => raise(
        [sprintf: "render-charts: can't draw ", v,
                  " with `render-charts`. Use `render-chart` instead."])
    | else => nothing
  end
  _ = cases (List<DataSeries>) lst:
    | empty => raise('render-charts: need at least one series to plot')
    | else => nothing
  end

  partitioned = partition(is-function-plot-series, lst)
  function-plots = partitioned.is-true.map(_.obj)
  is-show-samples = is-link(function-plots)
  shadow partitioned = partition(is-line-plot-series, partitioned.is-false)
  line-plots = partitioned.is-true.map(_.obj)
  scatter-plots = partitioned.is-false.map(_.obj)

  default-plot-chart-window-object.{
    method render(self):
      shadow self = self.{is-show-samples: is-show-samples}

      # don't let Google Charts infer x-min, x-max, y-min, y-max
      # infer them from Pyret side

      _ = check-render-x-axis(self)
      _ = check-render-y-axis(self)

      bbox = for map(plot-pts from line-plots.map(_.ps) +
                                   scatter-plots.map(_.ps)):
        for filter(pt from plot-pts):
          cases (Option) self.x-min:
            | none => true
            | some(v) => fst(pt) >= v
          end and
          cases (Option) self.x-max:
            | none => true
            | some(v) => fst(pt) <= v
          end and
          cases (Option) self.y-min:
            | none => true
            | some(v) => snd(pt) >= v
          end and
          cases (Option) self.y-max:
            | none => true
            | some(v) => snd(pt) <= v
          end
        end ^ get-bounding-box
      end ^ merge-bounding-box

      {x-min; x-max} = bound-result-to-bounds(
        get-bound-result(self.x-min, bbox, _.x-min),
        get-bound-result(self.x-max, bbox, _.x-max))

      shadow self = self.{x-min: x-min, x-max: x-max}

      function-plots-data = function-plots
        .map(generate-xy(_, self.x-min.value, self.x-max.value, self.num-samples))

      bbox-combined = link(bbox, function-plots-data.map(_.ps).map(get-bounding-box))
        ^ merge-bounding-box

      {y-min; y-max} = bound-result-to-bounds(
        get-bound-result(self.y-min, bbox-combined, _.y-min),
        get-bound-result(self.y-max, bbox-combined, _.y-max))

      shadow self = self.{y-min: y-min, y-max: y-max}

      fun helper(shadow self, shadow function-plots-data :: Option) -> IM.Image:
        shadow function-plots-data = cases (Option) function-plots-data:
          | none => function-plots
              .map(generate-xy(_, self.x-min.value, self.x-max.value, self.num-samples))
          | some(shadow function-plots-data) => function-plots-data
        end

        scatters-arr = for map(p from scatter-plots + function-plots-data):
          ps-to-arr(p.{ps: p.ps.filter(in-bound-xy(_, self))})
        end ^ reverse ^ builtins.raw-array-from-list

        lines-arr = for map(p from line-plots):
          ps-to-arr(p.{ps: line-plot-edge-cut(p.ps, self)})
        end ^ reverse ^ builtins.raw-array-from-list

        ret = P.plot(self, {scatters: scatters-arr, lines: lines-arr})
        cases (E.Either<Any, IM.Image>) ret:
          | left(new-self) => helper(new-self, none)
          | right(image) => image
        end
      end
      helper(self, some(function-plots-data))
    end
  } ^ plot-chart-window
where:
  p1 = from-list.function-plot(lam(x): x * x end).color(I.red)
  p2 = from-list.line-plot([list: 1, 2, 3, 4], [list: 1, 4, 9, 16]).color(I.green)
  p3 = from-list.histogram([list: 1, 2, 3, 4])
  p4 = from-list.line-plot(
      [list: -1, 1,  2, 3, 11, 8, 9],
      [list: 10, -1, 11, 9,  9, 3, 2])
  render-charts([list: p1, p2, p3]) raises ''
  render-charts([list: p1, p2])
    .title('quadratic function and a scatter plot')
    .x-min(0)
    .x-max(20)
    .y-min(0)
    .y-max(20)
    .get-image() does-not-raise
  render-charts([list: p4])
    .x-min(0)
    .x-max(10)
    .y-min(0)
    .y-max(10)
    .get-image() does-not-raise
end

from-list = {
  line-plot: line-plot-from-list,
  labeled-scatter-plot: labeled-scatter-plot-from-list,
  image-scatter-plot: image-scatter-plot-from-list,
  scatter-plot: scatter-plot-from-list,
  function-plot: function-plot-from-list,
  histogram: histogram-from-list,
  labeled-histogram: labeled-histogram-from-list,
  pie-chart: pie-chart-from-list,
  exploding-pie-chart: exploding-pie-chart-from-list,
  bar-chart: bar-chart-from-list,
  grouped-bar-chart: grouped-bar-chart-from-list,
  stacked-bar-chart: stacked-bar-chart-from-list,
  freq-bar-chart: freq-bar-chart-from-list,
  labeled-box-plot: labeled-box-plot-from-list,
  box-plot: box-plot-from-list,
}