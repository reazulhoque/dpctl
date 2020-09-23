##===------------- sycl_core.pyx - dpctl interface ------*- Cython -*------===##
##
##                      Data Parallel Control (dpctl)
##
## Copyright 2020 Intel Corporation
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
##===----------------------------------------------------------------------===##
##
## \file
## This file implements a sub-set of Sycl's interface using dpctl's CAPI.
##
##===----------------------------------------------------------------------===##

# distutils: language = c++
# cython: language_level=3

from __future__ import print_function
from enum import Enum, auto
import logging
from dpctl.backend cimport *


_logger = logging.getLogger(__name__)


class device_type(Enum):
    gpu = auto()
    cpu = auto()


cdef class UnsupportedDeviceTypeError(Exception):
    '''This exception is raised when a device type other than CPU or GPU is
       encountered.
    '''
    pass


cdef class SyclContext:

    @staticmethod
    cdef SyclContext _create (DPPLSyclContextRef ctxt):
        cdef SyclContext ret = SyclContext.__new__(SyclContext)
        ret.ctxt_ptr = ctxt
        return ret

    def __dealloc__ (self):
        DPPLContext_Delete(self.ctxt_ptr)

    cdef DPPLSyclContextRef get_context_ref (self):
        return self.ctxt_ptr


cdef class SyclDevice:
    ''' Wrapper class for a Sycl Device
    '''

    @staticmethod
    cdef SyclDevice _create (DPPLSyclDeviceRef dref):
        cdef SyclDevice ret = SyclDevice.__new__(SyclDevice)
        ret.device_ptr = dref
        ret.vendor_name = DPPLDevice_GetVendorName(dref)
        ret.device_name = DPPLDevice_GetName(dref)
        ret.driver_version = DPPLDevice_GetDriverInfo(dref)
        return ret

    def __dealloc__ (self):
        DPPLDevice_Delete(self.device_ptr)
        DPPLCString_Delete(self.device_name)
        DPPLCString_Delete(self.vendor_name)
        DPPLCString_Delete(self.driver_version)

    def dump_device_info (self):
        ''' Print information about the SYCL device.
        '''
        DPPLDevice_DumpInfo(self.device_ptr)

    def get_device_name (self):
        ''' Returns the name of the device as a string
        '''
        return self.device_name

    def get_vendor_name (self):
        ''' Returns the device vendor name as a string
        '''
        return self.vendor_name

    def get_driver_version (self):
        ''' Returns the OpenCL software driver version as a string
            in the form: major number.minor number, if this SYCL
            device is an OpenCL device. Returns a string class
            with the value "1.2" if this SYCL device is a host device.
        '''
        return self.driver_version

    cdef DPPLSyclDeviceRef get_device_ptr (self):
        ''' Returns the DPPLSyclDeviceRef pointer for this class.
        '''
        return self.device_ptr

cdef class SyclKernel:
    ''' Wraps a sycl::kernel object created from an OpenCL interoperability
        kernel.
    '''

    @staticmethod
    cdef SyclKernel _create (DPPLSyclKernelRef kref):
        cdef SyclKernel ret = SyclKernel.__new__(SyclKernel)
        ret.kernel_ptr = kref
        return ret

    def __dealloc__ (self):
        DPPLKernel_Delete(self.kernel_ptr)
        DPPLCString_Delete(self.function_name)

    def get_function_name (self):
        ''' Returns the name of the Kernel function.
        '''
        return self.function_name

    def get_num_args (self):
        ''' Returns the number of arguments for this kernel function.
        '''
        return DPPLKernel_GetNumArgs(self.kernel_ptr)

    cdef DPPLSyclKernelRef get_kernel_ptr (self):
        ''' Returns the DPPLSyclKernelRef pointer for this SyclKernel.
        '''
        return self.kernel_ptr


cdef class SyclProgram:
    ''' Wraps a sycl::program object created from an OpenCL interoperability
        program.

        SyclProgram exposes the C API from dppl_sycl_program_interface.h. A
        SyclProgram can be created from either a source string or a SPIR-V
        binary file.
    '''

    @staticmethod
    cdef SyclProgram _create (DPPLSyclProgramRef pref):
        cdef SyclProgram ret = SyclProgram.__new__(SyclProgram)
        ret.program_ptr = pref
        return ret

    def __dealloc__ (self):
        DPPLProgram_Delete(self.program_ptr)

    cdef DPPLSyclProgramRef get_program_ptr (self):
        return self.program_ptr

    cpdef SyclKernel get_sycl_kernel(self, kernel_name):
        if isinstance(kernel_name, unicode):
            kernel_name = <unicode>kernel_name
            return SyclKernel._create(DPPLProgram_GetKernel(self.program_ptr,
                                                            kernel_name))
        else:
            TypeError("Expected kernel_name to be a string")

    def has_sycl_kernel(self, kernel_name):
        return DPPLProgram_HasKernel(self.program_ptr, kernel_name)


cdef class SyclQueue:
    ''' Wrapper class for a Sycl queue.
    '''

    @staticmethod
    cdef SyclQueue _create (DPPLSyclQueueRef qref):
        cdef SyclQueue ret = SyclQueue.__new__(SyclQueue)
        ret.queue_ptr = qref
        return ret

    def __dealloc__ (self):
        DPPLQueue_Delete(self.queue_ptr)

    cpdef SyclContext get_sycl_context (self):
        return SyclContext._create(DPPLQueue_GetContext(self.queue_ptr))

    cpdef SyclDevice get_sycl_device (self):
        return SyclDevice._create(DPPLQueue_GetDevice(self.queue_ptr))

    cdef DPPLSyclQueueRef get_queue_ref (self):
        return self.queue_ptr


cdef class _SyclQueueManager:
    def _set_as_current_queue (self, device_ty, device_id):
        cdef DPPLSyclQueueRef queue_ptr
        if device_ty == device_type.gpu:
            queue_ptr = DPPLQueueMgr_PushQueue(_device_type._GPU, device_id)
        elif device_ty == device_type.cpu:
            queue_ptr = DPPLQueueMgr_PushQueue(_device_type._CPU, device_id)
        else:
            e = UnsupportedDeviceTypeError("Device can only be cpu or gpu")
            raise e

        return SyclQueue._create(queue_ptr)

    def _remove_current_queue (self):
        DPPLQueueMgr_PopQueue()

    def has_sycl_platforms (self):
        cdef size_t num_platforms = DPPLPlatform_GetNumPlatforms()
        if num_platforms:
            return True
        else:
            return False

    def get_num_platforms (self):
        ''' Returns the number of available SYCL/OpenCL platforms.
        '''
        return DPPLPlatform_GetNumPlatforms()

    def get_num_activated_queues (self):
        ''' Return the number of currently activated queues for this thread.
        '''
        return DPPLQueueMgr_GetNumActivatedQueues()

    def get_current_queue (self):
        ''' Returns the activated SYCL queue as a PyCapsule.
        '''
        return SyclQueue._create(DPPLQueueMgr_GetCurrentQueue())

    def set_default_queue (self, device_ty, device_id):
        if device_ty == device_type.gpu:
            DPPLQueueMgr_SetAsDefaultQueue(_device_type._GPU, device_id)
        elif device_ty == device_type.cpu:
            DPPLQueueMgr_SetAsDefaultQueue(_device_type._CPU, device_id)
        else:
            e = UnsupportedDeviceTypeError("Device can only be cpu or gpu")
            raise e

    def has_gpu_queues (self):
        cdef size_t num = DPPLQueueMgr_GetNumGPUQueues()
        if num:
            return True
        else:
            return False

    def has_cpu_queues (self):
        cdef size_t num = DPPLQueueMgr_GetNumCPUQueues()
        if num:
            return True
        else:
            return False

    def dump (self):
        ''' Prints information about the Runtime object.
        '''
        DPPLPlatform_DumpInfo()

    def is_in_dppl_ctxt (self):
        cdef size_t num = DPPLQueueMgr_GetNumActivatedQueues()
        if num:
            return True
        else:
            return False

# This private instance of the _SyclQueueManager should not be directly
# accessed outside the module.
_qmgr = _SyclQueueManager()

# Global bound functions
dump                     = _qmgr.dump
get_current_queue        = _qmgr.get_current_queue
get_num_platforms        = _qmgr.get_num_platforms
get_num_activated_queues = _qmgr.get_num_activated_queues
has_cpu_queues           = _qmgr.has_cpu_queues
has_gpu_queues           = _qmgr.has_gpu_queues
has_sycl_platforms       = _qmgr.has_sycl_platforms
set_default_queue        = _qmgr.set_default_queue
is_in_dppl_ctxt          = _qmgr.is_in_dppl_ctxt


def create_program_from_source (SyclQueue q, unicode source, unicode copts=""):
    ''' Creates a Sycl interoperability program from an OpenCL source string.

        We use the DPPLProgram_CreateFromOCLSource() C API function to create
        a Sycl progrma from an OpenCL source program that can contain multiple
        kernels.

        Parameters:
                q (SyclQueue)   : The SyclQueue object wraps the Sycl device for
                                  which the program will be built.
                source (unicode): Source string for an OpenCL program.
                copts (unicode) : Optional compilation flags that will be used
                                  when compiling the program.

            Returns:
                program (SyclProgram): A SyclProgram object wrapping the
                                       syc::program returned by the C API.
    '''

    cdef DPPLSyclProgramRef Pref

    cdef bytes bSrc = source.encode('utf8')
    cdef bytes bCOpts = copts.encode('utf8')
    cdef const char *Src = <const char*>bSrc
    cdef const char *COpts = <const char*>bCOpts
    cdef DPPLSyclContextRef CRef = q.get_sycl_context().get_context_ref()
    Pref = DPPLProgram_CreateFromOCLSource(CRef, Src, COpts)

    return SyclProgram._create(Pref)


def create_program_from_spirv (SyclQueue q, char[:] IL):
    ''' Creates a Sycl interoperability program from an SPIR-V binary.

        We use the DPPLProgram_CreateFromOCLSpirv() C API function to create
        a Sycl progrma from an compiled SPIR-V binary file.

        Parameters:
                q (SyclQueue): The SyclQueue object wraps the Sycl device for
                               which the program will be built.
                IL (char[:]) : SPIR-V binary IL file for an OpenCL program.

            Returns:
                program (SyclProgram): A SyclProgram object wrapping the
                                       syc::program returned by the C API.
    '''

    cdef DPPLSyclProgramRef Pref
    cdef bytes bIL = IL.data
    cdef const void *spirvIL = <const void*>bIL
    cdef DPPLSyclContextRef CRef = q.get_sycl_context().get_context_ref()
    Pref = DPPLProgram_CreateFromOCLSpirv(CRef, spirvIL, len(IL))

    return SyclProgram._create(Pref)


from contextlib import contextmanager

@contextmanager
def device_context (dev=device_type.gpu, device_num=0):
    # Create a new device context and add it to the front of the runtime's
    # deque of active contexts (SyclQueueManager.active_contexts_).
    # Also return a reference to the context. The behavior allows consumers
    # of the context manager to either use the new context by indirectly
    # calling get_current_context, or use the returned context object directly.

    # If set_context is unable to create a new context an exception is raised.
    try:
        ctxt = None
        ctxt = _qmgr._set_as_current_queue(dev, device_num)
        yield ctxt
    finally:
        # Code to release resource
        if ctxt:
            _logger.debug(
                "Removing the context from the stack of active contexts")
            _qmgr._remove_current_queue()
        else:
            _logger.debug("No context was created so nothing to do")