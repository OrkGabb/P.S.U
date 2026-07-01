import inspect
from graphify import extract
print("extract function signature:", inspect.signature(extract.extract))
print("extract module file:", extract.__file__)
